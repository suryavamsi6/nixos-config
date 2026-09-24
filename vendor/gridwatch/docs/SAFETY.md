# Gridwatch safety model

Gridwatch starts read-only. Runtime calibration is a deep battery discharge, consumes battery life, and is not routine maintenance. A reported telemetry field such as `SELFTEST` is never treated as proof that a command is supported.

## Manual runtime workflow

The Back-UPS RS 1500G-IN has no verified non-interactive calibration driver. Gridwatch therefore monitors a manual procedure without stopping `apcupsd`, opening USB directly, switching mains, or bypassing the UPS shutdown policy.

Before preparation or scheduling, the agent requires:

- Fresh telemetry and online utility power.
- 100% reported charge.
- A 30–40% load made only of non-critical equipment.
- No overload, replace-battery, low-battery, or communication-loss state.
- No active workflow and no 30-day cooldown.

Preparation observes the load for one uninterrupted minute. Drift outside the safe envelope resets that observation. The agent then issues a random challenge that expires after ten minutes. Starting requires Polkit authorization, the exact challenge, explicit acknowledgement of a non-critical load, and a three-second confirmation delay.

After confirmation, the operator—not Gridwatch—disconnects mains. The agent watches for on-battery state, tracks discharge, asks for mains restoration at 10% charge or low-battery status, and verifies recharge to at least 99%. It persists every transition so an agent restart can resume monitoring conservatively. Communication loss, overload, replace-battery state, invalid transitions, timeout, or an operator request moves the workflow to an aborted/blocked state with safe recovery guidance.

## Privilege and audit boundary

Read-only RPC is restricted by the Unix-socket group. Every mutation is tied to verified `SO_PEERCRED` identity and a Polkit authorization check. Requests and frames are bounded and timed out. Successful and rejected mutations are written to the SQLite audit log with the peer identity and reason; challenge tokens are not copied into the audit detail.

Automatic self-test and software calibration remain unavailable until an exact backend/model driver is independently verified. Capability reports are agent-owned and default to false.
