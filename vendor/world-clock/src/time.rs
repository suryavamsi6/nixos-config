use crate::model::{CityInput, ClockOutput};
use anyhow::{anyhow, Result};
use chrono::{DateTime, Offset, Utc};
use chrono_tz::Tz;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TimeFormat {
    TwelveHour,
    TwentyFourHour,
}

impl TimeFormat {
    pub fn parse(value: &str) -> Self {
        if value.eq_ignore_ascii_case("12h") {
            Self::TwelveHour
        } else {
            Self::TwentyFourHour
        }
    }

    fn pattern(self) -> &'static str {
        match self {
            Self::TwelveHour => "%-I:%M %p",
            Self::TwentyFourHour => "%H:%M",
        }
    }
}

pub fn parse_reference(value: Option<&str>) -> Result<DateTime<Utc>> {
    value
        .map(|raw| {
            DateTime::parse_from_rfc3339(raw)
                .map(|value| value.with_timezone(&Utc))
                .map_err(|error| anyhow!("invalid RFC 3339 time {raw:?}: {error}"))
        })
        .transpose()
        .map(|value| value.unwrap_or_else(Utc::now))
}

pub fn system_timezone() -> (String, Tz) {
    let name = std::env::var("TZ")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .or_else(|| iana_time_zone::get_timezone().ok())
        .unwrap_or_else(|| "UTC".to_string());
    match name.parse::<Tz>() {
        Ok(zone) => (name, zone),
        Err(_) => ("UTC".to_string(), chrono_tz::UTC),
    }
}

pub fn clock_for(
    city: &CityInput,
    reference: DateTime<Utc>,
    local_zone: Tz,
    format: TimeFormat,
) -> Result<ClockOutput> {
    if city.id.trim().is_empty() {
        return Err(anyhow!("city id is empty"));
    }
    if city.place.trim().is_empty() {
        return Err(anyhow!("place name is empty"));
    }
    if city.place.chars().count() > 120
        || city.label.as_deref().unwrap_or_default().chars().count() > 120
    {
        return Err(anyhow!("place or label is too long"));
    }
    validate_coordinate_pair(city.latitude, city.longitude)?;

    let zone: Tz = city
        .timezone
        .parse()
        .map_err(|_| anyhow!("unknown IANA timezone {}", city.timezone))?;
    let zoned = reference.with_timezone(&zone);
    let local = reference.with_timezone(&local_zone);
    let day_delta = zoned
        .date_naive()
        .signed_duration_since(local.date_naive())
        .num_days();
    let date = zoned.format("%a, %b %-d").to_string();
    let day_label = match day_delta {
        -1 => "Yesterday".to_string(),
        0 => "Today".to_string(),
        1 => "Tomorrow".to_string(),
        _ => date.clone(),
    };

    Ok(ClockOutput {
        id: city.id.clone(),
        place: city.place.trim().to_string(),
        label: city
            .label
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| city.place.trim())
            .to_string(),
        timezone: city.timezone.clone(),
        latitude: city.latitude,
        longitude: city.longitude,
        time: zoned.format(format.pattern()).to_string(),
        date,
        day_delta,
        day_label,
        abbreviation: zoned.format("%Z").to_string(),
        utc_offset_seconds: zoned.offset().fix().local_minus_utc(),
    })
}

pub fn validate_coordinate_pair(latitude: Option<f64>, longitude: Option<f64>) -> Result<()> {
    match (latitude, longitude) {
        (None, None) => Ok(()),
        (Some(lat), Some(lon))
            if lat.is_finite()
                && lon.is_finite()
                && (-90.0..=90.0).contains(&lat)
                && (-180.0..=180.0).contains(&lon) =>
        {
            Ok(())
        }
        (Some(_), Some(_)) => Err(anyhow!("coordinates are outside the world extent")),
        _ => Err(anyhow!("latitude and longitude must be supplied together")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn city(timezone: &str) -> CityInput {
        CityInput {
            id: "test".into(),
            place: "Test".into(),
            label: None,
            timezone: timezone.into(),
            latitude: Some(0.0),
            longitude: Some(0.0),
        }
    }

    #[test]
    fn new_york_observes_dst() {
        let winter = parse_reference(Some("2026-01-15T12:00:00Z")).unwrap();
        let summer = parse_reference(Some("2026-07-15T12:00:00Z")).unwrap();
        let winter_clock = clock_for(
            &city("America/New_York"),
            winter,
            chrono_tz::UTC,
            TimeFormat::TwentyFourHour,
        )
        .unwrap();
        let summer_clock = clock_for(
            &city("America/New_York"),
            summer,
            chrono_tz::UTC,
            TimeFormat::TwentyFourHour,
        )
        .unwrap();
        assert_eq!(winter_clock.time, "07:00");
        assert_eq!(winter_clock.utc_offset_seconds, -18_000);
        assert_eq!(summer_clock.time, "08:00");
        assert_eq!(summer_clock.utc_offset_seconds, -14_400);
    }

    #[test]
    fn kolkata_is_half_hour_without_dst() {
        for at in ["2026-01-15T12:00:00Z", "2026-07-15T12:00:00Z"] {
            let clock = clock_for(
                &city("Asia/Kolkata"),
                parse_reference(Some(at)).unwrap(),
                chrono_tz::UTC,
                TimeFormat::TwentyFourHour,
            )
            .unwrap();
            assert_eq!(clock.time, "17:30");
            assert_eq!(clock.utc_offset_seconds, 19_800);
        }
    }

    #[test]
    fn reports_date_line_day_delta() {
        let at = parse_reference(Some("2026-09-05T12:30:00Z")).unwrap();
        let tomorrow = clock_for(
            &city("Pacific/Kiritimati"),
            at,
            chrono_tz::UTC,
            TimeFormat::TwentyFourHour,
        )
        .unwrap();
        let yesterday = clock_for(
            &city("Pacific/Pago_Pago"),
            at,
            chrono_tz::Pacific::Kiritimati,
            TimeFormat::TwentyFourHour,
        )
        .unwrap();
        assert_eq!(tomorrow.day_delta, 1);
        assert_eq!(tomorrow.day_label, "Tomorrow");
        assert_eq!(yesterday.day_delta, -1);
    }

    #[test]
    fn renders_twelve_hour_time_on_request() {
        let at = parse_reference(Some("2026-09-05T00:05:00Z")).unwrap();
        let clock = clock_for(&city("UTC"), at, chrono_tz::UTC, TimeFormat::TwelveHour).unwrap();
        assert_eq!(clock.time, "12:05 AM");
    }
}
