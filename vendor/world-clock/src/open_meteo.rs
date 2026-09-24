use crate::model::{CityInput, SearchResult};
use crate::time::{clock_for, TimeFormat};
use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use chrono_tz::Tz;
use serde::Deserialize;
use std::time::Duration;

#[derive(Debug, Deserialize)]
struct GeocodingResponse {
    #[serde(default)]
    results: Vec<GeocodingPlace>,
}

#[derive(Debug, Deserialize)]
struct GeocodingPlace {
    name: String,
    latitude: f64,
    longitude: f64,
    timezone: String,
    #[serde(default)]
    admin1: Option<String>,
    #[serde(default)]
    country: Option<String>,
    #[serde(default)]
    country_code: Option<String>,
}

pub fn search(
    query: &str,
    language: &str,
    reference: DateTime<Utc>,
    local_zone: Tz,
    format: TimeFormat,
) -> Result<Vec<SearchResult>> {
    let language = if language.len() == 2 && language.chars().all(|ch| ch.is_ascii_alphabetic()) {
        language.to_ascii_lowercase()
    } else {
        "en".to_string()
    };
    let url = format!(
        "https://geocoding-api.open-meteo.com/v1/search?name={}&count=8&language={}&format=json",
        urlencoding::encode(query),
        language
    );
    let agent = ureq::AgentBuilder::new()
        .timeout_connect(Duration::from_secs(3))
        .timeout_read(Duration::from_secs(5))
        .timeout_write(Duration::from_secs(3))
        .build();
    let response: GeocodingResponse = agent
        .get(&url)
        .set("User-Agent", "serpantinum-world-clock/0.1")
        .call()
        .context("Open-Meteo geocoding request failed")?
        .into_json()
        .context("Open-Meteo returned invalid JSON")?;
    Ok(normalize_response(response, reference, local_zone, format))
}

fn normalize_response(
    response: GeocodingResponse,
    reference: DateTime<Utc>,
    local_zone: Tz,
    format: TimeFormat,
) -> Vec<SearchResult> {
    response
        .results
        .into_iter()
        .filter_map(|place| {
            let country = place.country.or(place.country_code).unwrap_or_default();
            let subtitle = match (place.admin1.as_deref(), country.as_str()) {
                (Some(admin), country) if !admin.is_empty() && admin != country => {
                    format!("{admin}, {country}")
                }
                (_, country) => country.to_string(),
            };
            let city = CityInput {
                id: "search".into(),
                place: place.name.clone(),
                label: None,
                timezone: place.timezone.clone(),
                latitude: Some(place.latitude),
                longitude: Some(place.longitude),
            };
            let clock = clock_for(&city, reference, local_zone, format).ok()?;
            Some(SearchResult {
                source: "online".into(),
                place: place.name,
                subtitle,
                timezone: place.timezone,
                latitude: Some(place.latitude),
                longitude: Some(place.longitude),
                time: clock.time,
                date: clock.date,
                day_delta: clock.day_delta,
                day_label: clock.day_label,
                abbreviation: clock.abbreviation,
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_fixture_and_drops_invalid_zones() {
        let fixture = r#"{
          "results": [
            {"name":"Bengaluru","latitude":12.97,"longitude":77.59,"timezone":"Asia/Kolkata","admin1":"Karnataka","country":"India"},
            {"name":"Broken","latitude":0.0,"longitude":0.0,"timezone":"Not/AZone","country_code":"XX"}
          ]
        }"#;
        let decoded: GeocodingResponse = serde_json::from_str(fixture).unwrap();
        let at = DateTime::parse_from_rfc3339("2026-09-05T12:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let results = normalize_response(decoded, at, chrono_tz::UTC, TimeFormat::TwentyFourHour);
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].place, "Bengaluru");
        assert_eq!(results[0].subtitle, "Karnataka, India");
        assert_eq!(results[0].time, "17:30");
    }
}
