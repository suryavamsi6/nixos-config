use crate::apc;
use anyhow::{anyhow, Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    fs,
    io::{Read, Write},
    os::unix::fs::OpenOptionsExt,
    path::{Path, PathBuf},
};

const LOAD_OBSERVATION_MS: i64 = 60_000;
const CHALLENGE_TTL_MS: i64 = 10 * 60_000;
const MAX_RUN_MS: i64 = 8 * 60 * 60_000;
const CALIBRATION_COOLDOWN_MS: i64 = 180 * 24 * 60 * 60_000;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Phase {
    Idle,
    Scheduled,
    ObservingLoad,
    Prepared,
    Running,
    AwaitingMains,
    Recharging,
    Completed,
    Aborted,
    Blocked,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MaintenanceState {
    pub phase: Phase,
    pub operation: Option<String>,
    pub progress: f64,
    pub message: String,
    pub scheduled_at: Option<i64>,
    pub stable_since: Option<i64>,
    pub prepared_at: Option<i64>,
    pub challenge_expires_at: Option<i64>,
    pub started_at: Option<i64>,
    pub updated_at: i64,
    pub cooldown_until: Option<i64>,
    pub baseline_runtime_minutes: Option<f64>,
    pub result_runtime_minutes: Option<f64>,
    pub seen_on_battery: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    challenge: Option<String>,
}

impl Default for MaintenanceState {
    fn default() -> Self {
        Self {
            phase: Phase::Idle,
            operation: None,
            progress: 0.0,
            message: "No maintenance operation is active.".into(),
            scheduled_at: None,
            stable_since: None,
            prepared_at: None,
            challenge_expires_at: None,
            started_at: None,
            updated_at: chrono::Utc::now().timestamp_millis(),
            cooldown_until: None,
            baseline_runtime_minutes: None,
            result_runtime_minutes: None,
            seen_on_battery: false,
            challenge: None,
        }
    }
}

pub struct Maintenance {
    path: PathBuf,
    state: MaintenanceState,
}

impl Maintenance {
    pub fn load(root: &Path) -> Self {
        let path = root.join("maintenance.json");
        let mut state = fs::read(&path)
            .ok()
            .and_then(|bytes| serde_json::from_slice::<MaintenanceState>(&bytes).ok())
            .unwrap_or_default();
        if matches!(
            state.phase,
            Phase::Running | Phase::AwaitingMains | Phase::Recharging
        ) {
            state.phase = Phase::Aborted;
            state.message = "The agent restarted during maintenance. The automatic workflow is stopped; verify mains power and apcupsd before trying again.".into();
            state.updated_at = chrono::Utc::now().timestamp_millis();
        }
        let maintenance = Self { path, state };
        let _ = maintenance.persist();
        maintenance
    }

    pub fn capabilities(status: &Value) -> Value {
        let raw = status.get("raw").and_then(Value::as_str).unwrap_or("");
        let model = apc::text_field(raw, "MODEL").unwrap_or("Unknown APC UPS");
        json!({
            "selfTest": false,
            "runtimeCalibration": false,
            "manualCalibration": true,
            "selfTestResultReported": apc::text_field(raw, "SELFTEST").is_some(),
            "model": model,
            "reason": "No non-interactive apcupsd maintenance driver has been proven safe for this model. Gridwatch provides a monitored manual calibration instead."
        })
    }

    pub fn public_status(&self) -> Value {
        serde_json::to_value(&self.state).unwrap_or_else(|_| json!({ "phase": "blocked" }))
    }

    pub fn prepare_manual_calibration(&mut self, status: &Value, now: i64) -> Result<Value> {
        if self
            .state
            .cooldown_until
            .is_some_and(|cooldown| cooldown > now)
        {
            return Err(anyhow!("calibration cooldown is still active"));
        }
        validate_preconditions(status)?;
        self.state = MaintenanceState {
            phase: Phase::ObservingLoad,
            operation: Some("manual-calibration".into()),
            progress: 0.0,
            message: "Keep a stable 30–40% non-critical load connected for one minute.".into(),
            stable_since: Some(now),
            baseline_runtime_minutes: metric(status, "TIMELEFT"),
            updated_at: now,
            ..MaintenanceState::default()
        };
        self.persist()?;
        Ok(self.public_status())
    }

    pub fn schedule_manual_calibration(
        &mut self,
        status: &Value,
        scheduled_at: i64,
        now: i64,
    ) -> Result<Value> {
        validate_preconditions(status)?;
        if scheduled_at < now + 60_000 || scheduled_at > now + 90 * 24 * 60 * 60_000 {
            return Err(anyhow!(
                "schedule must be between one minute and 90 days from now"
            ));
        }
        self.state = MaintenanceState {
            phase: Phase::Scheduled,
            operation: Some("manual-calibration".into()),
            progress: 0.0,
            message: "Manual calibration is scheduled. Preconditions will be checked again before it starts.".into(),
            scheduled_at: Some(scheduled_at),
            baseline_runtime_minutes: metric(status, "TIMELEFT"),
            updated_at: now,
            ..MaintenanceState::default()
        };
        self.persist()?;
        Ok(self.public_status())
    }

    pub fn confirm(
        &mut self,
        token: &str,
        acknowledged: bool,
        held_ms: u64,
        now: i64,
    ) -> Result<Value> {
        if self.state.phase != Phase::Prepared {
            return Err(anyhow!("maintenance is not ready for confirmation"));
        }
        if !acknowledged || held_ms < 3_000 {
            return Err(anyhow!(
                "non-critical load acknowledgement and a three-second hold are required"
            ));
        }
        if self.state.challenge.as_deref() != Some(token)
            || self
                .state
                .challenge_expires_at
                .is_none_or(|expires| expires < now)
        {
            return Err(anyhow!("maintenance challenge is invalid or expired"));
        }
        self.state.phase = Phase::Running;
        self.state.progress = 0.0;
        self.state.started_at = Some(now);
        self.state.updated_at = now;
        self.state.challenge = None;
        self.state.message = "Monitoring manual discharge. Disconnect mains only when it is safe; Gridwatch will never switch power itself.".into();
        self.persist()?;
        Ok(self.public_status())
    }

    pub fn abort(&mut self, reason: &str, now: i64) -> Result<Value> {
        self.state.phase = Phase::Aborted;
        self.state.message = format!(
            "Maintenance stopped: {reason}. Reconnect mains and verify normal UPS service."
        );
        self.state.updated_at = now;
        self.state.challenge = None;
        self.persist()?;
        Ok(self.public_status())
    }

    pub fn tick(&mut self, status: &Value, now: i64) -> Result<()> {
        match self.state.phase {
            Phase::Scheduled if self.state.scheduled_at.is_some_and(|at| at <= now) => {
                if validate_preconditions(status).is_ok() {
                    self.state.phase = Phase::ObservingLoad;
                    self.state.stable_since = Some(now);
                    self.state.message =
                        "Scheduled window opened. Observing load stability for one minute.".into();
                } else {
                    self.state.phase = Phase::Blocked;
                    self.state.message = "Scheduled calibration was blocked because live safety preconditions failed.".into();
                }
                self.state.updated_at = now;
                self.persist()?;
            }
            Phase::ObservingLoad => {
                if validate_preconditions(status).is_err() {
                    self.state.stable_since = Some(now);
                    self.state.progress = 0.0;
                    self.state.message =
                        "The safety envelope changed. Stable-load observation restarted.".into();
                } else {
                    let stable_since = self.state.stable_since.unwrap_or(now);
                    let elapsed = now.saturating_sub(stable_since);
                    self.state.progress =
                        (elapsed as f64 / LOAD_OBSERVATION_MS as f64 * 100.0).clamp(0.0, 100.0);
                    if elapsed >= LOAD_OBSERVATION_MS {
                        self.state.phase = Phase::Prepared;
                        self.state.prepared_at = Some(now);
                        self.state.challenge_expires_at = Some(now + CHALLENGE_TTL_MS);
                        self.state.challenge = Some(challenge()?);
                        self.state.message = "Safety checks passed. Confirm the non-critical load and hold for three seconds.".into();
                    }
                }
                self.state.updated_at = now;
                self.persist()?;
            }
            Phase::Prepared
                if self
                    .state
                    .challenge_expires_at
                    .is_some_and(|expires| expires < now) =>
            {
                self.state.phase = Phase::Blocked;
                self.state.challenge = None;
                self.state.message =
                    "The confirmation challenge expired. Run preparation again.".into();
                self.state.updated_at = now;
                self.persist()?;
            }
            Phase::Running => {
                if !available(status) {
                    self.abort("UPS communication was lost", now)?;
                    return Ok(());
                }
                if self
                    .state
                    .started_at
                    .is_some_and(|started| now.saturating_sub(started) > MAX_RUN_MS)
                {
                    self.abort("the eight-hour safety timeout was reached", now)?;
                    return Ok(());
                }
                let raw = status.get("raw").and_then(Value::as_str).unwrap_or("");
                let ups_status = apc::text_field(raw, "STATUS").unwrap_or("UNKNOWN");
                let battery = apc::numeric_field(raw, "BCHARGE");
                if ups_status.contains("OB") {
                    self.state.seen_on_battery = true;
                    if let Some(battery) = battery {
                        self.state.progress = (100.0 - battery).clamp(0.0, 75.0) / 75.0 * 100.0;
                        self.state.message =
                            format!("Manual discharge in progress — {battery:.0}% charge remains.");
                        if battery <= 25.0 {
                            self.state.phase = Phase::AwaitingMains;
                            self.state.message = "Target discharge reached. Reconnect mains now; Gridwatch is waiting for the UPS to return online.".into();
                        }
                    }
                } else if self.state.seen_on_battery && ups_status.contains("OL") {
                    self.state.phase = Phase::Recharging;
                    self.state.message = "Mains restored. Verifying a complete recharge.".into();
                }
                self.state.updated_at = now;
                self.persist()?;
            }
            Phase::AwaitingMains => {
                let raw = status.get("raw").and_then(Value::as_str).unwrap_or("");
                if apc::text_field(raw, "STATUS").is_some_and(|value| value.contains("OL")) {
                    self.state.phase = Phase::Recharging;
                    self.state.message = "Mains restored. Verifying a complete recharge.".into();
                    self.state.updated_at = now;
                    self.persist()?;
                }
            }
            Phase::Recharging if metric(status, "BCHARGE").is_some_and(|charge| charge >= 99.0) => {
                self.state.phase = Phase::Completed;
                self.state.progress = 100.0;
                self.state.result_runtime_minutes = metric(status, "TIMELEFT");
                self.state.cooldown_until = Some(now + CALIBRATION_COOLDOWN_MS);
                self.state.message =
                    "Manual calibration record completed after a verified full recharge.".into();
                self.state.updated_at = now;
                self.persist()?;
            }
            _ => {}
        }
        Ok(())
    }

    fn persist(&self) -> Result<()> {
        let parent = self
            .path
            .parent()
            .context("maintenance path has no parent")?;
        fs::create_dir_all(parent)?;
        let temp = self
            .path
            .with_extension(format!("tmp.{}", std::process::id()));
        let _ = fs::remove_file(&temp);
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o640)
            .open(&temp)?;
        serde_json::to_writer_pretty(&mut file, &self.state)?;
        file.write_all(b"\n")?;
        file.sync_all()?;
        fs::rename(&temp, &self.path)?;
        fs::File::open(parent)?.sync_all()?;
        Ok(())
    }
}

fn validate_preconditions(status: &Value) -> Result<()> {
    if !available(status) {
        return Err(anyhow!("UPS communication must be healthy"));
    }
    let raw = status.get("raw").and_then(Value::as_str).unwrap_or("");
    let ups_status = apc::text_field(raw, "STATUS").unwrap_or("UNKNOWN");
    if !ups_status.contains("OL") {
        return Err(anyhow!("UPS must be online"));
    }
    if apc::numeric_field(raw, "BCHARGE").unwrap_or(0.0) < 100.0 {
        return Err(anyhow!("battery must be fully charged"));
    }
    let load = apc::numeric_field(raw, "LOADPCT").unwrap_or(0.0);
    if !(30.0..=40.0).contains(&load) {
        return Err(anyhow!("a stable 30–40% non-critical load is required"));
    }
    Ok(())
}

fn available(status: &Value) -> bool {
    status.get("available").and_then(Value::as_bool) == Some(true)
}

fn metric(status: &Value, key: &str) -> Option<f64> {
    apc::numeric_field(status.get("raw")?.as_str()?, key)
}

fn challenge() -> Result<String> {
    let mut bytes = [0_u8; 16];
    fs::File::open("/dev/urandom")?.read_exact(&mut bytes)?;
    Ok(bytes.iter().map(|byte| format!("{byte:02x}")).collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn online(load: f64, battery: f64, status: &str) -> Value {
        json!({
            "available": true,
            "raw": format!("MODEL : Back-UPS RS 1500G-IN\nSTATUS : {status}\nLOADPCT : {load} Percent\nBCHARGE : {battery} Percent\nTIMELEFT : 10 Minutes\nSELFTEST : NO\n")
        })
    }

    #[test]
    fn observes_load_before_issuing_a_challenge() {
        let root = tempfile::tempdir().unwrap();
        let mut maintenance = Maintenance::load(root.path());
        maintenance
            .prepare_manual_calibration(&online(35.0, 100.0, "OL"), 1_000)
            .unwrap();
        maintenance
            .tick(&online(35.0, 100.0, "OL"), 62_000)
            .unwrap();
        assert_eq!(maintenance.state.phase, Phase::Prepared);
        assert!(maintenance.state.challenge.is_some());
    }

    #[test]
    fn aborts_on_communication_loss() {
        let root = tempfile::tempdir().unwrap();
        let mut maintenance = Maintenance::load(root.path());
        maintenance.state.phase = Phase::Running;
        maintenance.state.started_at = Some(1_000);
        maintenance
            .tick(&json!({"available": false}), 2_000)
            .unwrap();
        assert_eq!(maintenance.state.phase, Phase::Aborted);
    }

    #[test]
    fn completes_only_after_discharge_mains_return_and_recharge() {
        let root = tempfile::tempdir().unwrap();
        let mut maintenance = Maintenance::load(root.path());
        maintenance.state.phase = Phase::Running;
        maintenance.state.started_at = Some(1_000);
        maintenance.tick(&online(35.0, 24.0, "OB"), 2_000).unwrap();
        assert_eq!(maintenance.state.phase, Phase::AwaitingMains);
        maintenance.tick(&online(35.0, 50.0, "OL"), 3_000).unwrap();
        assert_eq!(maintenance.state.phase, Phase::Recharging);
        maintenance.tick(&online(35.0, 100.0, "OL"), 4_000).unwrap();
        assert_eq!(maintenance.state.phase, Phase::Completed);
        assert!(maintenance.state.cooldown_until.is_some());
    }
}
