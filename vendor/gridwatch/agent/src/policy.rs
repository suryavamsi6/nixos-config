use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{fs, io::Write, os::unix::fs::OpenOptionsExt, path::Path};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ShutdownAction {
    Shutdown,
    Hibernate,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Policy {
    pub battery_level: u8,
    pub minutes: u8,
    pub energy_rate: f64,
    pub raw_retention_hours: u16,
    pub minute_retention_days: u16,
    pub notify_on_battery: bool,
    pub notify_critical: bool,
    pub silent_hours_start: u8,
    pub silent_hours_end: u8,
    pub self_test_cadence_days: u16,
    pub shutdown_action: ShutdownAction,
}

impl Default for Policy {
    fn default() -> Self {
        Self {
            battery_level: 50,
            minutes: 5,
            energy_rate: 0.2,
            raw_retention_hours: 24,
            minute_retention_days: 90,
            notify_on_battery: true,
            notify_critical: true,
            silent_hours_start: 22,
            silent_hours_end: 7,
            self_test_cadence_days: 14,
            shutdown_action: ShutdownAction::Shutdown,
        }
    }
}

impl Policy {
    pub fn from_payload(value: &Value) -> Self {
        let defaults = Self::default();
        let energy_rate = number(value, "energyRate", defaults.energy_rate).clamp(0.0, 10.0);
        Self {
            battery_level: integer(value, "batteryLevel", defaults.battery_level as i64, 5, 90)
                as u8,
            minutes: integer(value, "minutes", defaults.minutes as i64, 1, 60) as u8,
            energy_rate: (energy_rate * 1_000.0).round() / 1_000.0,
            raw_retention_hours: integer(
                value,
                "rawRetentionHours",
                defaults.raw_retention_hours as i64,
                1,
                168,
            ) as u16,
            minute_retention_days: integer(
                value,
                "minuteRetentionDays",
                defaults.minute_retention_days as i64,
                1,
                3_650,
            ) as u16,
            notify_on_battery: boolean(value, "notifyOnBattery", defaults.notify_on_battery),
            notify_critical: boolean(value, "notifyCritical", defaults.notify_critical),
            silent_hours_start: integer(
                value,
                "silentHoursStart",
                defaults.silent_hours_start as i64,
                0,
                23,
            ) as u8,
            silent_hours_end: integer(
                value,
                "silentHoursEnd",
                defaults.silent_hours_end as i64,
                0,
                23,
            ) as u8,
            self_test_cadence_days: integer(
                value,
                "selfTestCadenceDays",
                defaults.self_test_cadence_days as i64,
                0,
                365,
            ) as u16,
            shutdown_action: if value.get("shutdownAction").and_then(Value::as_str)
                == Some("hibernate")
            {
                ShutdownAction::Hibernate
            } else {
                ShutdownAction::Shutdown
            },
        }
    }

    pub fn load(root: &Path) -> Self {
        fs::read(root.join("policy.json"))
            .ok()
            .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
            .map(|value| Self::from_payload(&value))
            .unwrap_or_default()
    }

    pub fn persist(&self, root: &Path) -> Result<()> {
        fs::create_dir_all(root)?;
        let target = root.join("policy.json");
        let temp = root.join(format!("policy.json.tmp.{}", std::process::id()));
        let _ = fs::remove_file(&temp);
        let mut options = fs::OpenOptions::new();
        options.write(true).create_new(true).mode(0o640);
        let mut file = options.open(&temp).context("create policy staging file")?;
        let result = (|| -> Result<()> {
            serde_json::to_writer_pretty(&mut file, self)?;
            file.write_all(b"\n")?;
            file.sync_all()?;
            fs::rename(&temp, &target)?;
            fs::File::open(root)?.sync_all()?;
            Ok(())
        })();
        if result.is_err() {
            let _ = fs::remove_file(temp);
        }
        result
    }
}

fn integer(value: &Value, key: &str, fallback: i64, minimum: i64, maximum: i64) -> i64 {
    value
        .get(key)
        .and_then(Value::as_i64)
        .unwrap_or(fallback)
        .clamp(minimum, maximum)
}

fn number(value: &Value, key: &str, fallback: f64) -> f64 {
    value
        .get(key)
        .and_then(Value::as_f64)
        .filter(|number| number.is_finite())
        .unwrap_or(fallback)
}

fn boolean(value: &Value, key: &str, fallback: bool) -> bool {
    value.get(key).and_then(Value::as_bool).unwrap_or(fallback)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clamps_untrusted_values() {
        let policy = Policy::from_payload(&serde_json::json!({
            "batteryLevel": 200,
            "minutes": -4,
            "energyRate": 99,
            "rawRetentionHours": 0
        }));
        assert_eq!(policy.battery_level, 90);
        assert_eq!(policy.minutes, 1);
        assert_eq!(policy.energy_rate, 10.0);
        assert_eq!(policy.raw_retention_hours, 1);
    }

    #[test]
    fn persists_and_loads_atomically() {
        let root = tempfile::tempdir().unwrap();
        let policy = Policy {
            battery_level: 35,
            minutes: 7,
            ..Policy::default()
        };
        policy.persist(root.path()).unwrap();
        assert_eq!(Policy::load(root.path()), policy);
    }
}
