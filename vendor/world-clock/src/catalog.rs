use crate::model::{CityInput, SearchResult};
use crate::time::{clock_for, TimeFormat};
use crate::timezone_grid::timezone_at;
use chrono::{DateTime, Utc};
use chrono_tz::{Tz, TZ_VARIANTS};
use deunicode::deunicode;
use serde::Deserialize;
use std::cmp::Ordering;
use std::collections::{HashMap, HashSet};

const CATALOG: &str = include_str!("../data/featured-cities.json");

#[derive(Clone, Debug, Deserialize)]
struct FeaturedCity {
    title: String,
    latitude: f64,
    longitude: f64,
    minimum_zoom: f64,
    source_label_rank: i64,
    source_population: i64,
}

#[derive(Clone)]
struct RankedCity {
    city: FeaturedCity,
    timezone: String,
    score: i64,
}

fn normalize(value: &str) -> String {
    deunicode(value).to_lowercase().replace(['_', '-'], " ")
}

fn text_score(candidate: &str, query: &str) -> Option<i64> {
    if candidate == query {
        Some(0)
    } else if candidate.starts_with(query) {
        Some(10 + (candidate.len() - query.len()) as i64)
    } else if candidate
        .split_whitespace()
        .any(|word| word.starts_with(query))
    {
        Some(30)
    } else {
        candidate.find(query).map(|index| 60 + index as i64)
    }
}

fn featured() -> Vec<FeaturedCity> {
    serde_json::from_str(CATALOG).unwrap_or_default()
}

pub fn search(
    query: &str,
    reference: DateTime<Utc>,
    local_zone: Tz,
    format: TimeFormat,
    limit: usize,
) -> Vec<SearchResult> {
    let normalized_query = normalize(query.trim());
    if normalized_query.is_empty() {
        return Vec::new();
    }

    let all_cities = featured();
    let mut ranked = all_cities
        .iter()
        .filter_map(|city| {
            let title = normalize(&city.title);
            let timezone = timezone_at(city.latitude, city.longitude)?;
            let score = text_score(&title, &normalized_query).or_else(|| {
                text_score(&normalize(&timezone), &normalized_query).map(|score| score + 25)
            })?;
            Some(RankedCity {
                city: city.clone(),
                timezone,
                score,
            })
        })
        .collect::<Vec<_>>();
    ranked.sort_by(|left, right| {
        left.score
            .cmp(&right.score)
            .then_with(|| {
                left.city
                    .minimum_zoom
                    .partial_cmp(&right.city.minimum_zoom)
                    .unwrap_or(Ordering::Equal)
            })
            .then_with(|| {
                left.city
                    .source_label_rank
                    .cmp(&right.city.source_label_rank)
            })
            .then_with(|| {
                right
                    .city
                    .source_population
                    .cmp(&left.city.source_population)
            })
            .then_with(|| left.city.title.cmp(&right.city.title))
    });

    let mut output = Vec::new();
    let mut seen = HashSet::new();
    for candidate in ranked {
        if output.len() >= limit {
            break;
        }
        let key = format!(
            "{}\0{}",
            normalize(&candidate.city.title),
            candidate.timezone
        );
        if !seen.insert(key) {
            continue;
        }
        if let Some(result) = result_for(
            &candidate.city.title,
            candidate.timezone,
            Some(candidate.city.latitude),
            Some(candidate.city.longitude),
            "local",
            reference,
            local_zone,
            format,
        ) {
            output.push(result);
        }
    }

    if output.len() < limit {
        let mut focus_by_zone = HashMap::new();
        for city in &all_cities {
            if let Some(zone) = timezone_at(city.latitude, city.longitude) {
                focus_by_zone
                    .entry(zone)
                    .or_insert((city.latitude, city.longitude));
            }
        }
        let mut zones = TZ_VARIANTS
            .iter()
            .filter_map(|zone| {
                let name = zone.name();
                text_score(&normalize(name), &normalized_query).map(|score| (score, name))
            })
            .collect::<Vec<_>>();
        zones.sort_by(|left, right| left.0.cmp(&right.0).then_with(|| left.1.cmp(right.1)));
        for (_, zone) in zones {
            if output.len() >= limit {
                break;
            }
            let place = zone.rsplit('/').next().unwrap_or(zone).replace('_', " ");
            let key = format!("{}\0{}", normalize(&place), zone);
            if !seen.insert(key) {
                continue;
            }
            let coordinates = focus_by_zone.get(zone).copied();
            if let Some(result) = result_for(
                &place,
                zone.to_string(),
                coordinates.map(|value| value.0),
                coordinates.map(|value| value.1),
                "timezone",
                reference,
                local_zone,
                format,
            ) {
                output.push(result);
            }
        }
    }

    output
}

#[allow(clippy::too_many_arguments)]
fn result_for(
    place: &str,
    timezone: String,
    latitude: Option<f64>,
    longitude: Option<f64>,
    source: &str,
    reference: DateTime<Utc>,
    local_zone: Tz,
    format: TimeFormat,
) -> Option<SearchResult> {
    let city = CityInput {
        id: "search".into(),
        place: place.to_string(),
        label: None,
        timezone: timezone.clone(),
        latitude,
        longitude,
    };
    let clock = clock_for(&city, reference, local_zone, format).ok()?;
    Some(SearchResult {
        source: source.into(),
        place: place.to_string(),
        subtitle: timezone.clone(),
        timezone,
        latitude,
        longitude,
        time: clock.time,
        date: clock.date,
        day_delta: clock.day_delta,
        day_label: clock.day_label,
        abbreviation: clock.abbreviation,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_bengaluru_offline_with_valid_timezone() {
        let at = DateTime::parse_from_rfc3339("2026-09-05T12:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let results = search(
            "Bengaluru",
            at,
            chrono_tz::UTC,
            TimeFormat::TwentyFourHour,
            8,
        );
        assert!(!results.is_empty());
        assert_eq!(results[0].place, "Bengaluru");
        assert_eq!(results[0].timezone, "Asia/Kolkata");
        assert!(results[0].latitude.is_some());
    }

    #[test]
    fn searches_iana_aliases() {
        let at = DateTime::parse_from_rfc3339("2026-09-05T12:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let results = search(
            "Kiritimati",
            at,
            chrono_tz::UTC,
            TimeFormat::TwentyFourHour,
            8,
        );
        assert!(results
            .iter()
            .any(|result| result.timezone == "Pacific/Kiritimati"));
    }
}
