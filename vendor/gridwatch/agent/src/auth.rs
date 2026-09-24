use anyhow::{anyhow, Context, Result};
use std::{path::PathBuf, time::Duration};
use tokio::{process::Command, time::timeout};

#[derive(Debug, Clone, Copy)]
pub struct Peer {
    pub uid: u32,
    pub gid: u32,
    pub pid: i32,
}

#[derive(Debug, Clone)]
pub struct Authorizer {
    pkcheck: PathBuf,
}

impl Authorizer {
    pub fn from_environment() -> Self {
        Self {
            pkcheck: std::env::var_os("GRIDWATCH_PKCHECK")
                .map(PathBuf::from)
                .unwrap_or_else(|| PathBuf::from("pkcheck")),
        }
    }

    pub async fn authorize_mutation(&self, peer: Peer) -> Result<()> {
        if peer.uid == 0 {
            return Ok(());
        }
        let start_time = process_start_time(peer.pid, peer.uid)?;
        let subject = format!("{},{},{}", peer.pid, start_time, peer.uid);
        let status = timeout(
            Duration::from_secs(90),
            Command::new(&self.pkcheck)
                .args([
                    "--action-id",
                    "org.gridwatch.maintenance",
                    "--process",
                    &subject,
                    "--allow-user-interaction",
                ])
                .status(),
        )
        .await
        .context("Polkit authorization timed out")??;
        if status.success() {
            Ok(())
        } else {
            Err(anyhow!("Polkit denied the requested mutation"))
        }
    }
}

fn process_start_time(pid: i32, expected_uid: u32) -> Result<u64> {
    if pid <= 0 {
        return Err(anyhow!("peer process id is unavailable"));
    }
    let status = std::fs::read_to_string(format!("/proc/{pid}/status"))
        .context("peer process disappeared")?;
    let uid = status
        .lines()
        .find_map(|line| line.strip_prefix("Uid:"))
        .and_then(|line| line.split_whitespace().next())
        .and_then(|value| value.parse::<u32>().ok())
        .context("could not verify peer uid")?;
    if uid != expected_uid {
        return Err(anyhow!("peer uid changed while authorizing"));
    }

    // The comm field can contain spaces and parentheses, so split after the final ')'.
    let stat = std::fs::read_to_string(format!("/proc/{pid}/stat"))?;
    let fields = stat
        .rsplit_once(')')
        .map(|(_, rest)| rest.trim())
        .context("invalid /proc stat record")?
        .split_whitespace()
        .collect::<Vec<_>>();
    // fields[0] is process state (field 3); starttime is field 22.
    fields
        .get(19)
        .context("missing process start time")?
        .parse::<u64>()
        .context("invalid process start time")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_current_process_identity() {
        let pid = std::process::id() as i32;
        let uid = unsafe { libc::geteuid() };
        assert!(process_start_time(pid, uid).unwrap() > 0);
    }
}
