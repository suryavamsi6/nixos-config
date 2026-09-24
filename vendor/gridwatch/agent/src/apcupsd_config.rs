use crate::{apc, policy::Policy};
use anyhow::{anyhow, Context, Result};
use std::{
    fs,
    io::Write,
    os::unix::fs::OpenOptionsExt,
    path::{Path, PathBuf},
    time::Duration,
};
use tokio::{process::Command, time::timeout};

const MAX_CONFIG_BYTES: usize = 64 * 1024;
const COMMAND_TIMEOUT: Duration = Duration::from_secs(20);

#[derive(Debug, Clone)]
pub struct ApcupsdConfig {
    config_path: PathBuf,
    systemctl: PathBuf,
    template_path: PathBuf,
}

impl ApcupsdConfig {
    pub fn from_environment() -> Option<Self> {
        let config_path = std::env::var_os("GRIDWATCH_APCUPSD_CONFIG")?;
        let systemctl = std::env::var_os("GRIDWATCH_SYSTEMCTL")?;
        let template_path = std::env::var_os("GRIDWATCH_APCUPSD_TEMPLATE")?;
        Some(Self {
            config_path: config_path.into(),
            systemctl: systemctl.into(),
            template_path: template_path.into(),
        })
    }

    /// Ensure a valid runtime configuration exists and matches the persisted policy at boot.
    /// If the module-provided file already exists, reconcile the thresholds (restarting when
    /// they differ). If it is missing, create one from the immutable template without
    /// disrupting a possibly running daemon.
    pub async fn ensure_present(&self, policy: &Policy) -> Result<()> {
        if self.config_path.exists() {
            return self.apply_policy(policy).await;
        }
        let template =
            fs::read(&self.template_path).context("read apcupsd configuration template")?;
        let rendered = render_policy(&template, policy)?;
        write_atomic(&self.config_path, &rendered)
            .context("write initial apcupsd configuration")?;
        Ok(())
    }
    pub async fn apply_policy(&self, policy: &Policy) -> Result<()> {
        reject_symlink(&self.config_path)?;
        let previous = fs::read(&self.config_path).context("read active apcupsd configuration")?;
        let rendered = render_policy(&previous, policy)?;
        if rendered == previous {
            return Ok(());
        }

        let rollback_path = self.config_path.with_extension("conf.last-good");
        write_atomic(&rollback_path, &previous)?;
        write_atomic(&self.config_path, &rendered)?;

        if let Err(problem) = self.restart_and_verify(policy).await {
            write_atomic(&self.config_path, &previous)
                .context("restore previous apcupsd configuration")?;
            return match self.restart_without_threshold_check().await {
                Ok(()) => Err(anyhow!(
                    "new apcupsd policy failed health verification and the previous configuration was restored: {problem:#}"
                )),
                Err(rollback) => Err(anyhow!(
                    "new apcupsd policy failed and rollback could not restore service health: apply error: {problem:#}; rollback error: {rollback:#}"
                )),
            };
        }
        Ok(())
    }

    async fn restart_and_verify(&self, policy: &Policy) -> Result<()> {
        self.restart().await?;
        for _ in 0..5 {
            let status = apc::status().await;
            if status.get("available").and_then(serde_json::Value::as_bool) == Some(true) {
                if let Some(raw) = status.get("raw").and_then(serde_json::Value::as_str) {
                    let (battery, minutes) = reported_thresholds(raw);
                    if battery == Some(u64::from(policy.battery_level))
                        && minutes == Some(u64::from(policy.minutes))
                    {
                        return Ok(());
                    }
                }
            }
            tokio::time::sleep(Duration::from_secs(1)).await;
        }
        Err(anyhow!(
            "apcupsd did not report the requested BATTERYLEVEL/MINUTES after restart"
        ))
    }

    async fn restart_without_threshold_check(&self) -> Result<()> {
        self.restart().await?;
        for _ in 0..5 {
            let status = apc::status().await;
            if status.get("available").and_then(serde_json::Value::as_bool) == Some(true) {
                return Ok(());
            }
            tokio::time::sleep(Duration::from_secs(1)).await;
        }
        Err(anyhow!("apcupsd did not recover after rollback"))
    }

    async fn restart(&self) -> Result<()> {
        let status = timeout(
            COMMAND_TIMEOUT,
            Command::new(&self.systemctl)
                .args(["restart", "apcupsd.service"])
                .status(),
        )
        .await
        .context("apcupsd restart timed out")??;
        if !status.success() {
            return Err(anyhow!("systemctl rejected the apcupsd restart"));
        }
        Ok(())
    }
}

fn render_policy(previous: &[u8], policy: &Policy) -> Result<Vec<u8>> {
    if previous.len() > MAX_CONFIG_BYTES {
        return Err(anyhow!("apcupsd configuration exceeds the safety limit"));
    }
    let text = std::str::from_utf8(previous).context("apcupsd configuration is not UTF-8")?;
    if !text
        .lines()
        .next()
        .is_some_and(|line| line.starts_with("## apcupsd.conf"))
    {
        return Err(anyhow!("unrecognized apcupsd configuration header"));
    }
    validate_loopback_nis(text)?;

    let mut battery_seen = false;
    let mut minutes_seen = false;
    let mut output = String::with_capacity(text.len() + 64);
    for line in text.lines() {
        let directive = line.split_whitespace().next().unwrap_or("");
        match directive {
            "BATTERYLEVEL" => {
                if !battery_seen {
                    output.push_str(&format!("BATTERYLEVEL {}\n", policy.battery_level));
                    battery_seen = true;
                }
            }
            "MINUTES" => {
                if !minutes_seen {
                    output.push_str(&format!("MINUTES {}\n", policy.minutes));
                    minutes_seen = true;
                }
            }
            _ => {
                output.push_str(line);
                output.push('\n');
            }
        }
    }
    if !battery_seen {
        output.push_str(&format!("BATTERYLEVEL {}\n", policy.battery_level));
    }
    if !minutes_seen {
        output.push_str(&format!("MINUTES {}\n", policy.minutes));
    }
    if output.len() > MAX_CONFIG_BYTES {
        return Err(anyhow!(
            "rendered apcupsd configuration exceeds the safety limit"
        ));
    }
    Ok(output.into_bytes())
}

fn validate_loopback_nis(text: &str) -> Result<()> {
    let mut nis_ip = None;
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let mut fields = trimmed.split_whitespace();
        if fields.next() == Some("NISIP") {
            let value = fields.next().unwrap_or("");
            if nis_ip.is_some() || value != "127.0.0.1" {
                return Err(anyhow!("apcupsd NIS must be uniquely bound to 127.0.0.1"));
            }
            nis_ip = Some(value);
        }
    }
    if nis_ip.is_none() {
        return Err(anyhow!(
            "apcupsd configuration must declare NISIP 127.0.0.1"
        ));
    }
    Ok(())
}

fn reported_thresholds(raw: &str) -> (Option<u64>, Option<u64>) {
    let mut battery = None;
    let mut minutes = None;
    for line in raw.lines() {
        let Some((key, value)) = line.split_once(':') else {
            continue;
        };
        let parsed = value
            .split_whitespace()
            .next()
            .and_then(|number| number.parse::<u64>().ok());
        match key.trim() {
            "MBATTCHG" => battery = parsed,
            "MINTIMEL" => minutes = parsed,
            _ => {}
        }
    }
    (battery, minutes)
}

fn reject_symlink(path: &Path) -> Result<()> {
    let metadata = fs::symlink_metadata(path).context("inspect apcupsd configuration")?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(anyhow!("apcupsd configuration must be a regular file"));
    }
    Ok(())
}

fn write_atomic(target: &Path, bytes: &[u8]) -> Result<()> {
    let parent = target
        .parent()
        .context("configuration path has no parent")?;
    let file_name = target
        .file_name()
        .and_then(|name| name.to_str())
        .context("configuration file name is invalid")?;
    let temp = parent.join(format!(".{file_name}.tmp.{}", std::process::id()));
    let _ = fs::remove_file(&temp);
    let mut options = fs::OpenOptions::new();
    options.write(true).create_new(true).mode(0o640);
    let mut file = options.open(&temp).context("create apcupsd staging file")?;
    let result = (|| -> Result<()> {
        file.write_all(bytes)?;
        file.sync_all()?;
        fs::rename(&temp, target)?;
        fs::File::open(parent)?.sync_all()?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(temp);
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    const BASE: &[u8] = b"## apcupsd.conf v1.1 ##\nUPSTYPE usb\nNISIP 127.0.0.1\nBATTERYLEVEL 50\nMINUTES 5\nSCRIPTDIR /nix/store/example\n";

    #[test]
    fn changes_only_bounded_shutdown_directives() {
        let policy = Policy {
            battery_level: 35,
            minutes: 7,
            ..Policy::default()
        };
        let rendered = String::from_utf8(render_policy(BASE, &policy).unwrap()).unwrap();
        assert!(rendered.contains("BATTERYLEVEL 35\n"));
        assert!(rendered.contains("MINUTES 7\n"));
        assert!(rendered.contains("SCRIPTDIR /nix/store/example\n"));
    }

    #[test]
    fn rejects_non_loopback_or_duplicate_nis_bindings() {
        let policy = Policy::default();
        let remote = String::from_utf8_lossy(BASE)
            .replace("127.0.0.1", "0.0.0.0")
            .into_bytes();
        assert!(render_policy(&remote, &policy).is_err());
        let mut duplicate = BASE.to_vec();
        duplicate.extend_from_slice(b"NISIP 127.0.0.1\n");
        assert!(render_policy(&duplicate, &policy).is_err());
    }

    #[test]
    fn parses_effective_thresholds_from_status() {
        assert_eq!(
            reported_thresholds("MBATTCHG : 35 Percent\nMINTIMEL : 7 Minutes\n"),
            (Some(35), Some(7))
        );
    }

    #[test]
    fn renders_missing_directives_when_template_lacks_them() {
        let policy = Policy {
            battery_level: 30,
            minutes: 6,
            ..Policy::default()
        };
        let sparse: &[u8] = b"## apcupsd.conf v1.1 ##\nUPSTYPE usb\nNISIP 127.0.0.1\n";
        let rendered = String::from_utf8(render_policy(sparse, &policy).unwrap()).unwrap();
        assert!(rendered.contains("BATTERYLEVEL 30\n"));
        assert!(rendered.contains("MINUTES 6\n"));
    }

    #[tokio::test]
    async fn ensure_present_creates_file_from_template_when_missing() {
        let root = tempfile::tempdir().unwrap();
        let template = root.path().join("apcupsd.template");
        let config = root.path().join("apcupsd.conf");
        let systemctl = root.path().join("systemctl");
        fs::write(&template, BASE).unwrap();
        let manager = ApcupsdConfig {
            config_path: config.clone(),
            systemctl,
            template_path: template,
        };
        let policy = Policy {
            battery_level: 40,
            minutes: 8,
            ..Policy::default()
        };
        manager.ensure_present(&policy).await.unwrap();
        let written = fs::read(&config).unwrap();
        assert!(String::from_utf8_lossy(&written).contains("BATTERYLEVEL 40\n"));
    }
}
