use crate::{apc, auth::Peer};
use anyhow::{Context, Result};
use rusqlite::{params, Connection};
use serde_json::{json, Value};
use std::{
    collections::hash_map::DefaultHasher,
    fs,
    hash::{Hash, Hasher},
    os::unix::fs::PermissionsExt,
    path::Path,
};

const MAX_EVENT_BYTES: usize = 1024 * 1024;

pub struct Storage {
    connection: Connection,
    last_status: Option<String>,
}

#[derive(Clone, Copy)]
struct Metrics {
    load: Option<f64>,
    battery: Option<f64>,
    runtime: Option<f64>,
    line: Option<f64>,
    battery_voltage: Option<f64>,
}

impl Storage {
    pub fn open(root: &Path) -> Result<Self> {
        fs::create_dir_all(root)?;
        let path = root.join("gridwatch.sqlite3");
        let connection = Connection::open(&path).context("open Gridwatch database")?;
        fs::set_permissions(&path, fs::Permissions::from_mode(0o640))?;
        connection.busy_timeout(std::time::Duration::from_secs(2))?;
        connection.execute_batch(
            "PRAGMA journal_mode=WAL;
             PRAGMA synchronous=NORMAL;
             PRAGMA foreign_keys=ON;
             CREATE TABLE IF NOT EXISTS schema_version(version INTEGER NOT NULL);
             INSERT INTO schema_version(version)
               SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM schema_version);
             CREATE TABLE IF NOT EXISTS samples_raw(
               at_ms INTEGER PRIMARY KEY,
               available INTEGER NOT NULL,
               payload_json TEXT NOT NULL
             );
             CREATE TABLE IF NOT EXISTS samples_minute(
               bucket_ms INTEGER PRIMARY KEY,
               load_sum REAL NOT NULL DEFAULT 0, load_count INTEGER NOT NULL DEFAULT 0,
               battery_sum REAL NOT NULL DEFAULT 0, battery_count INTEGER NOT NULL DEFAULT 0,
               runtime_sum REAL NOT NULL DEFAULT 0, runtime_count INTEGER NOT NULL DEFAULT 0,
               line_min REAL, line_max REAL,
               battery_voltage_sum REAL NOT NULL DEFAULT 0,
               battery_voltage_count INTEGER NOT NULL DEFAULT 0,
               samples INTEGER NOT NULL DEFAULT 0
             );
             CREATE TABLE IF NOT EXISTS samples_hour(
               bucket_ms INTEGER PRIMARY KEY,
               load_sum REAL NOT NULL DEFAULT 0, load_count INTEGER NOT NULL DEFAULT 0,
               battery_sum REAL NOT NULL DEFAULT 0, battery_count INTEGER NOT NULL DEFAULT 0,
               runtime_sum REAL NOT NULL DEFAULT 0, runtime_count INTEGER NOT NULL DEFAULT 0,
               line_min REAL, line_max REAL,
               battery_voltage_sum REAL NOT NULL DEFAULT 0,
               battery_voltage_count INTEGER NOT NULL DEFAULT 0,
               samples INTEGER NOT NULL DEFAULT 0
             );
             CREATE TABLE IF NOT EXISTS events(
               id INTEGER PRIMARY KEY AUTOINCREMENT,
               at_ms INTEGER NOT NULL,
               code TEXT NOT NULL,
               severity TEXT NOT NULL,
               message TEXT NOT NULL,
               source TEXT NOT NULL,
               fingerprint TEXT NOT NULL UNIQUE,
               acknowledged INTEGER NOT NULL DEFAULT 0
             );
             CREATE INDEX IF NOT EXISTS events_at ON events(at_ms DESC);
             CREATE TABLE IF NOT EXISTS audit(
               id INTEGER PRIMARY KEY AUTOINCREMENT,
               at_ms INTEGER NOT NULL,
               uid INTEGER NOT NULL,
               gid INTEGER NOT NULL,
               pid INTEGER NOT NULL,
               action TEXT NOT NULL,
               result TEXT NOT NULL,
               detail TEXT
             );",
        )?;
        Ok(Self {
            connection,
            last_status: None,
        })
    }

    pub fn store_sample(
        &mut self,
        at_ms: i64,
        payload: &Value,
        raw_retention_hours: u16,
        minute_retention_days: u16,
    ) -> Result<()> {
        let raw = payload.get("raw").and_then(Value::as_str).unwrap_or("");
        let metrics = Metrics {
            load: apc::numeric_field(raw, "LOADPCT"),
            battery: apc::numeric_field(raw, "BCHARGE"),
            runtime: apc::numeric_field(raw, "TIMELEFT"),
            line: apc::numeric_field(raw, "LINEV"),
            battery_voltage: apc::numeric_field(raw, "BATTV"),
        };
        let available = payload
            .get("available")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let transaction = self.connection.transaction()?;
        transaction.execute(
            "INSERT OR REPLACE INTO samples_raw(at_ms, available, payload_json) VALUES (?1, ?2, ?3)",
            params![at_ms, available, payload.to_string()],
        )?;
        upsert_rollup(
            &transaction,
            "samples_minute",
            at_ms / 60_000 * 60_000,
            metrics,
        )?;
        upsert_rollup(
            &transaction,
            "samples_hour",
            at_ms / 3_600_000 * 3_600_000,
            metrics,
        )?;
        let raw_retention_ms = i64::from(raw_retention_hours) * 60 * 60 * 1_000;
        let minute_retention_ms = i64::from(minute_retention_days) * 24 * 60 * 60 * 1_000;
        transaction.execute(
            "DELETE FROM samples_raw WHERE at_ms < ?1",
            [at_ms - raw_retention_ms],
        )?;
        transaction.execute(
            "DELETE FROM samples_minute WHERE bucket_ms < ?1",
            [at_ms - minute_retention_ms],
        )?;
        transaction.commit()?;

        let status = apc::text_field(raw, "STATUS")
            .unwrap_or(if available { "UNKNOWN" } else { "COMMLOST" })
            .to_owned();
        if self.last_status.as_deref() != Some(status.as_str()) {
            let severity = if status.contains("LB") || status.contains("COMMLOST") {
                "critical"
            } else if status.contains("OB") || status.contains("RB") {
                "warning"
            } else {
                "info"
            };
            self.insert_event(
                at_ms,
                "ups.status.changed",
                severity,
                &format!("UPS status changed to {status}"),
                "telemetry",
            )?;
            self.last_status = Some(status);
        }
        Ok(())
    }

    pub fn history(
        &self,
        from_ms: i64,
        to_ms: i64,
        resolution: &str,
        limit: usize,
    ) -> Result<Value> {
        let limit = limit.clamp(1, 2_000) as i64;
        if resolution == "raw" {
            let mut statement = self.connection.prepare(
                "SELECT at_ms, available, payload_json FROM samples_raw
                 WHERE at_ms BETWEEN ?1 AND ?2 ORDER BY at_ms ASC LIMIT ?3",
            )?;
            let rows = statement.query_map(params![from_ms, to_ms, limit], |row| {
                let payload: String = row.get(2)?;
                let mut value =
                    serde_json::from_str::<Value>(&payload).unwrap_or_else(|_| json!({}));
                if let Some(object) = value.as_object_mut() {
                    object.insert("timestamp".into(), json!(row.get::<_, i64>(0)?));
                    object.insert("available".into(), json!(row.get::<_, bool>(1)?));
                }
                Ok(value)
            })?;
            return Ok(Value::Array(rows.collect::<rusqlite::Result<Vec<_>>>()?));
        }

        let table = if resolution == "hour" {
            "samples_hour"
        } else {
            "samples_minute"
        };
        let sql = format!(
            "SELECT bucket_ms,
              CASE WHEN load_count=0 THEN NULL ELSE load_sum/load_count END,
              CASE WHEN battery_count=0 THEN NULL ELSE battery_sum/battery_count END,
              CASE WHEN runtime_count=0 THEN NULL ELSE runtime_sum/runtime_count END,
              line_min, line_max,
              CASE WHEN battery_voltage_count=0 THEN NULL ELSE battery_voltage_sum/battery_voltage_count END,
              samples
             FROM {table} WHERE bucket_ms BETWEEN ?1 AND ?2 ORDER BY bucket_ms ASC LIMIT ?3"
        );
        let mut statement = self.connection.prepare(&sql)?;
        let rows = statement.query_map(params![from_ms, to_ms, limit], |row| {
            Ok(json!({
                "timestamp": row.get::<_, i64>(0)?,
                "load": row.get::<_, Option<f64>>(1)?,
                "battery": row.get::<_, Option<f64>>(2)?,
                "runtime": row.get::<_, Option<f64>>(3)?,
                "lineMin": row.get::<_, Option<f64>>(4)?,
                "lineMax": row.get::<_, Option<f64>>(5)?,
                "batteryVoltage": row.get::<_, Option<f64>>(6)?,
                "samples": row.get::<_, i64>(7)?,
            }))
        })?;
        Ok(Value::Array(rows.collect::<rusqlite::Result<Vec<_>>>()?))
    }

    pub fn events(&self, limit: usize) -> Result<Value> {
        let mut statement = self.connection.prepare(
            "SELECT id, at_ms, code, severity, message, source, acknowledged
             FROM events ORDER BY at_ms DESC LIMIT ?1",
        )?;
        let rows = statement.query_map([limit.clamp(1, 500) as i64], |row| {
            Ok(json!({
                "id": row.get::<_, i64>(0)?.to_string(),
                "at": row.get::<_, i64>(1)?,
                "code": row.get::<_, String>(2)?,
                "severity": row.get::<_, String>(3)?,
                "message": row.get::<_, String>(4)?,
                "source": row.get::<_, String>(5)?,
                "acknowledged": row.get::<_, bool>(6)?,
            }))
        })?;
        Ok(Value::Array(rows.collect::<rusqlite::Result<Vec<_>>>()?))
    }

    pub fn import_event_file(&self, path: &Path) -> Result<usize> {
        let bytes = fs::read(path).unwrap_or_default();
        let start = bytes.len().saturating_sub(MAX_EVENT_BYTES);
        let text = String::from_utf8_lossy(&bytes[start..]);
        let now = chrono::Utc::now().timestamp_millis();
        let mut imported = 0;
        for line in text.lines().filter(|line| !line.trim().is_empty()) {
            let lower = line.to_ascii_lowercase();
            let severity = if lower.contains("exhaust") || lower.contains("shutdown") {
                "critical"
            } else if lower.contains("failure") || lower.contains("battery") {
                "warning"
            } else {
                "info"
            };
            imported +=
                self.insert_event(now, "apcupsd.event", severity, line.trim(), "apcupsd")? as usize;
        }
        Ok(imported)
    }

    pub fn audit(
        &self,
        peer: Peer,
        action: &str,
        result: &str,
        detail: Option<&str>,
    ) -> Result<()> {
        self.connection.execute(
            "INSERT INTO audit(at_ms, uid, gid, pid, action, result, detail)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![
                chrono::Utc::now().timestamp_millis(),
                peer.uid,
                peer.gid,
                peer.pid,
                action,
                result,
                detail
            ],
        )?;
        Ok(())
    }

    fn insert_event(
        &self,
        at_ms: i64,
        code: &str,
        severity: &str,
        message: &str,
        source: &str,
    ) -> Result<bool> {
        let mut hasher = DefaultHasher::new();
        code.hash(&mut hasher);
        message.hash(&mut hasher);
        let fingerprint = format!("{:016x}", hasher.finish());
        Ok(self.connection.execute(
            "INSERT OR IGNORE INTO events(at_ms, code, severity, message, source, fingerprint)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![at_ms, code, severity, message, source, fingerprint],
        )? > 0)
    }
}

fn upsert_rollup(
    transaction: &rusqlite::Transaction<'_>,
    table: &str,
    bucket_ms: i64,
    metrics: Metrics,
) -> Result<()> {
    let sql = format!(
        "INSERT INTO {table}(
          bucket_ms, load_sum, load_count, battery_sum, battery_count,
          runtime_sum, runtime_count, line_min, line_max,
          battery_voltage_sum, battery_voltage_count, samples)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?8, ?9, ?10, 1)
         ON CONFLICT(bucket_ms) DO UPDATE SET
          load_sum=load_sum+excluded.load_sum, load_count=load_count+excluded.load_count,
          battery_sum=battery_sum+excluded.battery_sum, battery_count=battery_count+excluded.battery_count,
          runtime_sum=runtime_sum+excluded.runtime_sum, runtime_count=runtime_count+excluded.runtime_count,
          line_min=CASE WHEN excluded.line_min IS NULL THEN line_min WHEN line_min IS NULL THEN excluded.line_min ELSE min(line_min, excluded.line_min) END,
          line_max=CASE WHEN excluded.line_max IS NULL THEN line_max WHEN line_max IS NULL THEN excluded.line_max ELSE max(line_max, excluded.line_max) END,
          battery_voltage_sum=battery_voltage_sum+excluded.battery_voltage_sum,
          battery_voltage_count=battery_voltage_count+excluded.battery_voltage_count,
          samples=samples+1"
    );
    transaction.execute(
        &sql,
        params![
            bucket_ms,
            metrics.load.unwrap_or(0.0),
            i64::from(metrics.load.is_some()),
            metrics.battery.unwrap_or(0.0),
            i64::from(metrics.battery.is_some()),
            metrics.runtime.unwrap_or(0.0),
            i64::from(metrics.runtime.is_some()),
            metrics.line,
            metrics.battery_voltage.unwrap_or(0.0),
            i64::from(metrics.battery_voltage.is_some()),
        ],
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn migrates_stores_and_queries_history() {
        let root = tempfile::tempdir().unwrap();
        let mut storage = Storage::open(root.path()).unwrap();
        storage
            .store_sample(
                1_700_000_000_000,
                &json!({"available":true,"raw":"STATUS : ONLINE\nLOADPCT : 25 Percent\nBCHARGE : 100 Percent\nTIMELEFT : 40 Minutes\nLINEV : 230 Volts\n"}),
                24,
                90,
            )
            .unwrap();
        let history = storage
            .history(1_699_999_000_000, 1_700_001_000_000, "minute", 100)
            .unwrap();
        assert_eq!(history.as_array().unwrap().len(), 1);
        assert_eq!(history[0]["load"], 25.0);
        assert!(!storage.events(10).unwrap().as_array().unwrap().is_empty());
    }

    #[test]
    fn event_import_is_deduplicated() {
        let root = tempfile::tempdir().unwrap();
        let event_path = root.path().join("events");
        fs::write(&event_path, "Power failure.\nMains returned.\n").unwrap();
        let storage = Storage::open(root.path()).unwrap();
        assert_eq!(storage.import_event_file(&event_path).unwrap(), 2);
        assert_eq!(storage.import_event_file(&event_path).unwrap(), 0);
    }
}
