mod apc;
mod apcupsd_config;
mod auth;
mod maintenance;
mod policy;
mod protocol;
mod storage;

use anyhow::{anyhow, Context, Result};
use apcupsd_config::ApcupsdConfig;
use auth::{Authorizer, Peer};
use maintenance::Maintenance;
use policy::Policy;
use protocol::{error, response, Request, Response, MAX_REQUEST_BYTES, VERSION};
use serde_json::{json, Value};
use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    sync::Arc,
    time::Duration,
};
use storage::Storage;
use tokio::{
    io::{AsyncBufRead, AsyncBufReadExt, AsyncWriteExt, BufReader},
    net::{UnixListener, UnixStream},
    sync::{Mutex, RwLock, Semaphore},
    time::{interval, timeout},
};

const DEFAULT_SOCKET: &str = "/run/gridwatch/agent.sock";
const DEFAULT_STATE: &str = "/var/lib/gridwatch";
const DEFAULT_EVENTS: &str = "/var/log/apcupsd.events";
const MAX_CONNECTIONS: usize = 32;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(120);

struct AppState {
    root: PathBuf,
    policy: RwLock<Policy>,
    storage: Mutex<Storage>,
    maintenance: Mutex<Maintenance>,
    apcupsd_config: Option<ApcupsdConfig>,
    authorizer: Authorizer,
    event_path: PathBuf,
}

impl AppState {
    async fn audit(&self, peer: Peer, action: &str, result: &str, detail: Option<&str>) {
        let _ = self
            .storage
            .lock()
            .await
            .audit(peer, action, result, detail);
    }

    async fn authorize(&self, peer: Peer, action: &str) -> Result<()> {
        match self.authorizer.authorize_mutation(peer).await {
            Ok(()) => {
                self.audit(peer, action, "authorized", None).await;
                Ok(())
            }
            Err(error) => {
                self.audit(peer, action, "denied", Some(&error.to_string()))
                    .await;
                Err(error)
            }
        }
    }
}

async fn handle(request: Request, peer: Peer, state: Arc<AppState>) -> Response {
    let request_id = request.request_id.clone();
    if let Err(code) = request.validate() {
        return error(
            code,
            "The request did not satisfy Gridwatch protocol v1.",
            request_id,
        );
    }

    match request.kind.as_str() {
        "ping" => response(
            "status",
            json!({
                "agent": "ready",
                "protocolVersion": VERSION,
                "capabilities": ["telemetry", "history", "events", "settings", "manual-calibration"]
            }),
            request_id,
        ),
        "status" => response("status", status_payload(&state).await, request_id),
        "settings" => {
            let policy = state.policy.read().await.clone();
            response(
                "settings",
                json!({ "effective": policy, "source": "agent" }),
                request_id,
            )
        }
        "history" => match history_payload(&request.payload, &state).await {
            Ok(payload) => response("history", payload, request_id),
            Err(problem) => error("invalid-history-query", &problem.to_string(), request_id),
        },
        "events" => {
            let limit = request
                .payload
                .get("limit")
                .and_then(Value::as_u64)
                .unwrap_or(100) as usize;
            match state.storage.lock().await.events(limit) {
                Ok(items) => response("events", json!({ "items": items }), request_id),
                Err(problem) => error("storage-error", &problem.to_string(), request_id),
            }
        }
        "set-settings" => {
            if let Err(problem) = state.authorize(peer, "set-settings").await {
                return error("authorization-denied", &problem.to_string(), request_id);
            }
            let next = Policy::from_payload(&request.payload);
            let previous = state.policy.read().await.clone();
            let shutdown_policy_changed =
                next.battery_level != previous.battery_level || next.minutes != previous.minutes;
            if shutdown_policy_changed {
                let Some(manager) = state.apcupsd_config.as_ref() else {
                    let message = "Gridwatch is not configured as the apcupsd policy owner; shutdown thresholds were not changed.";
                    state
                        .audit(peer, "set-settings", "rejected", Some(message))
                        .await;
                    return error("policy-owner-unavailable", message, request_id);
                };
                if let Err(problem) = manager.apply_policy(&next).await {
                    state
                        .audit(
                            peer,
                            "set-settings",
                            "apply-failed",
                            Some(&problem.to_string()),
                        )
                        .await;
                    return error("apcupsd-apply-failed", &problem.to_string(), request_id);
                }
            }
            if let Err(problem) = next.persist(&state.root) {
                let rollback = if shutdown_policy_changed {
                    match state.apcupsd_config.as_ref() {
                        Some(manager) => manager.apply_policy(&previous).await.err(),
                        None => None,
                    }
                } else {
                    None
                };
                let detail = match rollback {
                    Some(rollback) => format!(
                        "policy persistence failed ({problem:#}) and apcupsd rollback failed ({rollback:#})"
                    ),
                    None => problem.to_string(),
                };
                state
                    .audit(peer, "set-settings", "persistence-failed", Some(&detail))
                    .await;
                return error("persistence-failed", &detail, request_id);
            }
            *state.policy.write().await = next.clone();
            state.audit(peer, "set-settings", "accepted", None).await;
            response(
                "settings",
                json!({
                    "effective": next,
                    "result": "accepted",
                    "shutdownPolicyApplied": shutdown_policy_changed
                }),
                request_id,
            )
        }
        "action" => {
            let action = request
                .payload
                .get("action")
                .and_then(Value::as_str)
                .unwrap_or("unknown");
            if action == "maintenance-status" {
                let payload = state.maintenance.lock().await.public_status();
                return response("action", payload, request_id);
            }
            if action == "capabilities" {
                let status = apc::status().await;
                return response("action", Maintenance::capabilities(&status), request_id);
            }
            if let Err(problem) = state.authorize(peer, action).await {
                return error("authorization-denied", &problem.to_string(), request_id);
            }
            let now = chrono::Utc::now().timestamp_millis();
            let result = match action {
                "prepare-manual-calibration" => {
                    let status = apc::status().await;
                    state
                        .maintenance
                        .lock()
                        .await
                        .prepare_manual_calibration(&status, now)
                }
                "schedule-manual-calibration" => {
                    let status = apc::status().await;
                    let scheduled_at = request
                        .payload
                        .get("scheduledAt")
                        .and_then(Value::as_i64)
                        .unwrap_or(0);
                    state
                        .maintenance
                        .lock()
                        .await
                        .schedule_manual_calibration(&status, scheduled_at, now)
                }
                "confirm-maintenance" => {
                    let token = request
                        .payload
                        .get("token")
                        .and_then(Value::as_str)
                        .unwrap_or("");
                    let acknowledged = request
                        .payload
                        .get("acknowledgedNonCriticalLoad")
                        .and_then(Value::as_bool)
                        .unwrap_or(false);
                    let held_ms = request
                        .payload
                        .get("heldMs")
                        .and_then(Value::as_u64)
                        .unwrap_or(0);
                    state
                        .maintenance
                        .lock()
                        .await
                        .confirm(token, acknowledged, held_ms, now)
                }
                "abort-maintenance" => {
                    let reason = request
                        .payload
                        .get("reason")
                        .and_then(Value::as_str)
                        .unwrap_or("requested by operator");
                    state.maintenance.lock().await.abort(reason, now)
                }
                "prepare-self-test" => Err(anyhow!(
                    "Automatic self-test is not exposed because no safe non-interactive driver was verified for this UPS. Use the guided front-panel procedure.",
                )),
                _ => Err(anyhow!("unknown maintenance action")),
            };
            match result {
                Ok(payload) => {
                    state.audit(peer, action, "accepted", None).await;
                    response("action", payload, request_id)
                }
                Err(problem) => {
                    state
                        .audit(peer, action, "rejected", Some(&problem.to_string()))
                        .await;
                    error("maintenance-rejected", &problem.to_string(), request_id)
                }
            }
        }
        _ => error(
            "unknown-kind",
            "Unknown Gridwatch request kind.",
            request_id,
        ),
    }
}

async fn status_payload(state: &AppState) -> Value {
    let mut status = apc::status().await;
    let capabilities = Maintenance::capabilities(&status);
    let maintenance = state.maintenance.lock().await.public_status();
    if let Some(object) = status.as_object_mut() {
        object.insert("capabilities".into(), capabilities);
        object.insert("maintenance".into(), maintenance);
    }
    status
}

async fn history_payload(payload: &Value, state: &AppState) -> Result<Value> {
    let now = chrono::Utc::now().timestamp_millis();
    let from = payload
        .get("from")
        .and_then(Value::as_i64)
        .unwrap_or(now - 24 * 60 * 60 * 1_000);
    let to = payload.get("to").and_then(Value::as_i64).unwrap_or(now);
    if from > to {
        return Err(anyhow!("history start must not be after its end"));
    }
    let resolution = payload
        .get("resolution")
        .and_then(Value::as_str)
        .unwrap_or("minute");
    if !matches!(resolution, "raw" | "minute" | "hour") {
        return Err(anyhow!("resolution must be raw, minute, or hour"));
    }
    let limit = payload
        .get("limit")
        .and_then(Value::as_u64)
        .unwrap_or(1_000) as usize;
    let items = state
        .storage
        .lock()
        .await
        .history(from, to, resolution, limit)?;
    Ok(json!({ "items": items, "from": from, "to": to, "resolution": resolution }))
}

async fn sample(state: Arc<AppState>) {
    let status = apc::status().await;
    let at = status
        .get("sampledAt")
        .and_then(Value::as_i64)
        .unwrap_or_else(|| chrono::Utc::now().timestamp_millis());
    if let Err(error) = state.maintenance.lock().await.tick(&status, at) {
        eprintln!("gridwatch-agent: maintenance state update failed: {error:#}");
    }
    let policy = state.policy.read().await.clone();
    let mut storage = state.storage.lock().await;
    if let Err(error) = storage.store_sample(
        at,
        &status,
        policy.raw_retention_hours,
        policy.minute_retention_days,
    ) {
        eprintln!("gridwatch-agent: telemetry storage failed: {error:#}");
    }
    if let Err(error) = storage.import_event_file(&state.event_path) {
        eprintln!("gridwatch-agent: event import failed: {error:#}");
    }
}

async fn serve_client(stream: UnixStream, peer: Peer, state: Arc<AppState>) -> Result<()> {
    let (read_half, mut write_half) = stream.into_split();
    let mut reader = BufReader::with_capacity(8 * 1024, read_half);
    while let Some(frame) = read_frame(&mut reader).await? {
        let output = match serde_json::from_slice::<Request>(&frame) {
            Ok(request) => {
                match timeout(REQUEST_TIMEOUT, handle(request, peer, state.clone())).await {
                    Ok(response) => response,
                    Err(_) => error("request-timeout", "The agent request timed out.", None),
                }
            }
            Err(problem) => error("invalid-json", &problem.to_string(), None),
        };
        let mut encoded = serde_json::to_vec(&output)?;
        encoded.push(b'\n');
        write_half.write_all(&encoded).await?;
    }
    Ok(())
}

async fn read_frame<R: AsyncBufRead + Unpin>(reader: &mut R) -> Result<Option<Vec<u8>>> {
    let mut frame = Vec::with_capacity(1024);
    loop {
        let available = reader.fill_buf().await?;
        if available.is_empty() {
            if frame.is_empty() {
                return Ok(None);
            }
            return Err(anyhow!("unterminated Gridwatch request"));
        }
        if let Some(position) = available.iter().position(|byte| *byte == b'\n') {
            if frame.len() + position > MAX_REQUEST_BYTES {
                return Err(anyhow!(
                    "Gridwatch request exceeded {MAX_REQUEST_BYTES} bytes"
                ));
            }
            frame.extend_from_slice(&available[..position]);
            reader.consume(position + 1);
            if frame.last() == Some(&b'\r') {
                frame.pop();
            }
            return Ok(Some(frame));
        }
        if frame.len() + available.len() > MAX_REQUEST_BYTES {
            return Err(anyhow!(
                "Gridwatch request exceeded {MAX_REQUEST_BYTES} bytes"
            ));
        }
        let consumed = available.len();
        frame.extend_from_slice(available);
        reader.consume(consumed);
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    let socket = std::env::var("GRIDWATCH_SOCKET").unwrap_or_else(|_| DEFAULT_SOCKET.into());
    let root =
        PathBuf::from(std::env::var("GRIDWATCH_STATE").unwrap_or_else(|_| DEFAULT_STATE.into()));
    let event_path = PathBuf::from(
        std::env::var("GRIDWATCH_APC_EVENTS").unwrap_or_else(|_| DEFAULT_EVENTS.into()),
    );
    fs::create_dir_all(&root)?;
    let policy = Policy::load(&root);
    let storage = Storage::open(&root)?;
    let maintenance = Maintenance::load(&root);
    let apcupsd_config = ApcupsdConfig::from_environment();
    if let Some(manager) = apcupsd_config.as_ref() {
        if let Err(problem) = manager.ensure_present(&policy).await {
            eprintln!(
                "gridwatch-agent: initial apcupsd shutdown policy reconciliation failed: {problem:#}"
            );
        }
    }
    let state = Arc::new(AppState {
        root,
        policy: RwLock::new(policy),
        storage: Mutex::new(storage),
        maintenance: Mutex::new(maintenance),
        apcupsd_config,
        authorizer: Authorizer::from_environment(),
        event_path,
    });

    let socket_path = Path::new(&socket);
    if let Some(parent) = socket_path.parent() {
        fs::create_dir_all(parent)?;
    }
    let _ = fs::remove_file(socket_path);
    let listener = UnixListener::bind(socket_path).context("bind Gridwatch agent socket")?;
    fs::set_permissions(socket_path, fs::Permissions::from_mode(0o660))?;

    let sampler = state.clone();
    tokio::spawn(async move {
        let mut ticker = interval(Duration::from_secs(5));
        loop {
            ticker.tick().await;
            sample(sampler.clone()).await;
        }
    });

    let connections = Arc::new(Semaphore::new(MAX_CONNECTIONS));
    loop {
        let (stream, _) = listener.accept().await?;
        let credentials = match stream.peer_cred() {
            Ok(credentials) => credentials,
            Err(error) => {
                eprintln!("gridwatch-agent: rejected peer without credentials: {error}");
                continue;
            }
        };
        let Some(pid) = credentials.pid() else {
            eprintln!("gridwatch-agent: rejected peer without a process id");
            continue;
        };
        let peer = Peer {
            uid: credentials.uid(),
            gid: credentials.gid(),
            pid,
        };
        let Ok(permit) = connections.clone().try_acquire_owned() else {
            eprintln!("gridwatch-agent: connection limit reached");
            continue;
        };
        let state = state.clone();
        tokio::spawn(async move {
            let _permit = permit;
            if let Err(error) = serve_client(stream, peer, state).await {
                eprintln!("gridwatch-agent: client error: {error:#}");
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn rejects_oversized_frames_without_allocating_the_payload() {
        let mut bytes = vec![b'a'; MAX_REQUEST_BYTES + 1];
        bytes.push(b'\n');
        let mut reader = BufReader::with_capacity(1024, bytes.as_slice());
        assert!(read_frame(&mut reader).await.is_err());
    }

    #[tokio::test]
    async fn reads_one_newline_delimited_frame() {
        let mut reader = BufReader::new(&b"{\"version\":1}\n"[..]);
        assert_eq!(
            read_frame(&mut reader).await.unwrap().unwrap(),
            b"{\"version\":1}".to_vec()
        );
    }
}
