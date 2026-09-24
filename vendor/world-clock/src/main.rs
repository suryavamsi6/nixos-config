mod catalog;
mod model;
mod open_meteo;
mod time;
mod timezone_grid;

use anyhow::{anyhow, bail, Context, Result};
use model::{CityInput, SearchPayload, SnapshotError, SnapshotPayload};
use std::env;
use time::{clock_for, parse_reference, system_timezone, TimeFormat};

const SCHEMA_VERSION: u8 = 1;
const VERSION: &str = env!("CARGO_PKG_VERSION");
const USAGE: &str = "Usage: serpantinum-world-clock-backend <snapshot|search|version> [options]";

fn flag<'a>(args: &'a [String], name: &str) -> Option<&'a str> {
    args.windows(2)
        .find(|pair| pair[0] == name)
        .map(|pair| pair[1].as_str())
}

fn required_flag<'a>(args: &'a [String], name: &str) -> Result<&'a str> {
    flag(args, name).ok_or_else(|| anyhow!("missing required flag {name}"))
}

fn parse_bool(value: Option<&str>) -> bool {
    matches!(value, Some("true" | "1" | "yes"))
}

fn snapshot(args: &[String]) -> Result<SnapshotPayload> {
    let raw = required_flag(args, "--cities-json")?;
    if raw.len() > 256 * 1024 {
        bail!("city payload is too large");
    }
    let cities: Vec<CityInput> =
        serde_json::from_str(raw).context("invalid --cities-json payload")?;
    if cities.len() > 128 {
        bail!("at most 128 cities are supported");
    }
    let reference = parse_reference(flag(args, "--at"))?;
    let format = TimeFormat::parse(flag(args, "--format").unwrap_or("24h"));
    let (local_timezone, local_zone) = system_timezone();
    let mut clocks = Vec::new();
    let mut errors = Vec::new();
    for city in cities {
        match clock_for(&city, reference, local_zone, format) {
            Ok(clock) => clocks.push(clock),
            Err(error) => errors.push(SnapshotError {
                id: city.id,
                timezone: city.timezone,
                message: error.to_string(),
            }),
        }
    }
    Ok(SnapshotPayload {
        schema_version: SCHEMA_VERSION,
        generated_at: reference.to_rfc3339(),
        local_timezone,
        clocks,
        errors,
    })
}

fn search(args: &[String]) -> Result<SearchPayload> {
    let query = required_flag(args, "--query")?.trim();
    if query.chars().count() > 120 {
        bail!("search query is too long");
    }
    let reference = parse_reference(flag(args, "--at"))?;
    let format = TimeFormat::parse(flag(args, "--format").unwrap_or("24h"));
    let (_, local_zone) = system_timezone();
    let mut results = catalog::search(query, reference, local_zone, format, 8);
    let online_enabled = parse_bool(flag(args, "--online"));
    let online_attempted = results.is_empty() && online_enabled && query.chars().count() >= 2;
    let mut error = None;
    let mut source = if results.is_empty() { "none" } else { "local" }.to_string();
    if online_attempted {
        match open_meteo::search(
            query,
            flag(args, "--language").unwrap_or("en"),
            reference,
            local_zone,
            format,
        ) {
            Ok(remote) => {
                results = remote;
                source = if results.is_empty() { "none" } else { "online" }.to_string();
            }
            Err(remote_error) => error = Some(remote_error.to_string()),
        }
    }
    Ok(SearchPayload {
        schema_version: SCHEMA_VERSION,
        query: query.to_string(),
        source,
        online_attempted,
        results,
        error,
    })
}

fn execute(args: &[String]) -> Result<String> {
    let Some((command, remaining)) = args.split_first() else {
        bail!(USAGE);
    };
    match command.as_str() {
        "snapshot" => Ok(serde_json::to_string(&snapshot(remaining)?)?),
        "search" => Ok(serde_json::to_string(&search(remaining)?)?),
        "version" | "--version" => Ok(format!("serpantinum-world-clock-backend {VERSION}")),
        "help" | "--help" | "-h" => Ok(USAGE.to_string()),
        other => bail!("unknown command {other:?}\n{USAGE}"),
    }
}

fn main() {
    let args = env::args().skip(1).collect::<Vec<_>>();
    match execute(&args) {
        Ok(output) => println!("{output}"),
        Err(error) => {
            eprintln!("{error:#}");
            std::process::exit(2);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn snapshot_keeps_valid_clocks_when_one_zone_is_invalid() {
        let args = vec![
            "--cities-json".into(),
            r#"[{"id":"a","place":"Tokyo","timezone":"Asia/Tokyo"},{"id":"b","place":"Broken","timezone":"Nope/Zone"}]"#.into(),
            "--at".into(),
            "2026-09-05T12:00:00Z".into(),
            "--format".into(),
            "24h".into(),
        ];
        let payload = snapshot(&args).unwrap();
        assert_eq!(payload.clocks.len(), 1);
        assert_eq!(payload.errors.len(), 1);
        assert_eq!(payload.clocks[0].time, "21:00");
    }

    #[test]
    fn disabled_online_search_never_attempts_network() {
        let args = vec![
            "--query".into(),
            "definitely-not-a-real-city-zzzz".into(),
            "--online".into(),
            "false".into(),
            "--at".into(),
            "2026-09-05T12:00:00Z".into(),
        ];
        let payload = search(&args).unwrap();
        assert!(!payload.online_attempted);
        assert!(payload.results.is_empty());
    }

    #[test]
    fn offline_hit_suppresses_online_fallback() {
        let args = vec![
            "--query".into(),
            "Bengaluru".into(),
            "--online".into(),
            "true".into(),
            "--at".into(),
            "2026-09-05T12:00:00Z".into(),
        ];
        let payload = search(&args).unwrap();
        assert_eq!(payload.source, "local");
        assert!(!payload.online_attempted);
        assert_eq!(payload.results[0].timezone, "Asia/Kolkata");
    }
}
