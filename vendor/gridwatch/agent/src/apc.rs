use anyhow::{anyhow, Context, Result};
use serde_json::{json, Value};
use std::{path::PathBuf, process::Stdio, time::Duration};
use tokio::{
    io::{AsyncRead, AsyncReadExt},
    process::Command,
    time::timeout,
};

const MAX_OUTPUT_BYTES: usize = 256 * 1024;
const COMMAND_TIMEOUT: Duration = Duration::from_secs(5);

pub async fn status() -> Value {
    match run_apcaccess().await {
        Ok(raw) => json!({
            "available": true,
            "raw": raw,
            "sampledAt": chrono::Utc::now().timestamp_millis()
        }),
        Err(error) => json!({
            "available": false,
            "error": error.to_string(),
            "sampledAt": chrono::Utc::now().timestamp_millis()
        }),
    }
}

async fn run_apcaccess() -> Result<String> {
    let program = std::env::var_os("GRIDWATCH_APCACCESS")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("apcaccess"));
    let mut child = Command::new(program)
        .arg("status")
        .kill_on_drop(true)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .context("could not start apcaccess")?;
    let stdout = child.stdout.take().context("missing apcaccess stdout")?;
    let stderr = child.stderr.take().context("missing apcaccess stderr")?;

    let (stdout, stderr, process_status) = timeout(COMMAND_TIMEOUT, async move {
        tokio::join!(read_bounded(stdout), read_bounded(stderr), child.wait())
    })
    .await
    .context("apcaccess timed out")?;
    let stdout = stdout?;
    let stderr = stderr?;
    let process_status = process_status?;
    if !process_status.success() {
        let detail = String::from_utf8_lossy(&stderr);
        return Err(anyhow!("apcaccess failed: {}", detail.trim()));
    }
    String::from_utf8(stdout).context("apcaccess returned non-UTF-8 output")
}

async fn read_bounded<R: AsyncRead + Unpin>(reader: R) -> Result<Vec<u8>> {
    let mut bytes = Vec::new();
    reader
        .take((MAX_OUTPUT_BYTES + 1) as u64)
        .read_to_end(&mut bytes)
        .await?;
    if bytes.len() > MAX_OUTPUT_BYTES {
        return Err(anyhow!("apcaccess output exceeded the safety limit"));
    }
    Ok(bytes)
}

pub fn numeric_field(raw: &str, key: &str) -> Option<f64> {
    raw.lines().find_map(|line| {
        let (name, value) = line.split_once(':')?;
        if name.trim() != key {
            return None;
        }
        value
            .split_whitespace()
            .next()?
            .replace(',', ".")
            .parse::<f64>()
            .ok()
    })
}

pub fn text_field<'a>(raw: &'a str, key: &str) -> Option<&'a str> {
    raw.lines().find_map(|line| {
        let (name, value) = line.split_once(':')?;
        (name.trim() == key).then(|| value.trim())
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_apc_fields() {
        let raw = "STATUS   : ONLINE\nLOADPCT  : 42.5 Percent\n";
        assert_eq!(text_field(raw, "STATUS"), Some("ONLINE"));
        assert_eq!(numeric_field(raw, "LOADPCT"), Some(42.5));
    }
}
