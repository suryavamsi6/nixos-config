import { useEffect, useRef, useState } from 'react'
import { colors, styles } from '../../app/theme'
import { preflightCalibration } from '../../domain/calibration'
import {
  capabilityProbe,
  type MaintenanceStatus,
  type UpsTelemetry,
} from '../../domain/ups'
import { Card, Progress, SectionTitle } from '../../ui/primitives'
import { ActionButton, DataRow, StatePanel, Tag } from '../shared'

export function CalibrationView({
  telemetry,
  onAction,
}: {
  telemetry: UpsTelemetry
  onAction: (
    action: string,
    parameters?: Record<string, unknown>,
  ) => Promise<void>
}) {
  const capabilities = capabilityProbe(telemetry)
  const preflight = preflightCalibration(telemetry)
  const maintenance = telemetry.maintenance ?? idleMaintenance()
  const softwareCalibration = capabilities.supported.includes(
    'runtime-calibration',
  )
  const selfTest = capabilities.supported.includes('self-test')
  const [acknowledged, setAcknowledged] = useState(false)
  const [busy, setBusy] = useState(false)
  const [confirming, setConfirming] = useState(false)
  const [holdReady, setHoldReady] = useState(false)
  const holdStartedAt = useRef<number | null>(null)
  const holdTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const [operationError, setOperationError] = useState<string | null>(null)
  const readiness = [
    telemetry.status === 'online',
    !telemetry.stale,
    (telemetry.batteryPercent ?? 0) >= 100,
    (telemetry.loadPercent ?? 0) >= 30 && (telemetry.loadPercent ?? 100) <= 40,
  ]
  const score = Math.round(
    (readiness.filter(Boolean).length / readiness.length) * 100,
  )

  const run = async (
    action: string,
    parameters: Record<string, unknown> = {},
  ) => {
    setBusy(true)
    setOperationError(null)
    try {
      await onAction(action, parameters)
    } catch (error) {
      setOperationError(error instanceof Error ? error.message : String(error))
    } finally {
      setBusy(false)
    }
  }

  const cancelHold = () => {
    if (holdTimer.current) clearTimeout(holdTimer.current)
    holdTimer.current = null
    holdStartedAt.current = null
    setConfirming(false)
    setHoldReady(false)
  }

  useEffect(() => () => cancelHold(), [])

  const startHold = () => {
    if (!acknowledged || !maintenance.challenge || busy) return
    setOperationError(null)
    setConfirming(true)
    setHoldReady(false)
    holdStartedAt.current = Date.now()
    holdTimer.current = setTimeout(() => setHoldReady(true), 3_000)
  }

  const finishHold = () => {
    const startedAt = holdStartedAt.current
    const heldMs = startedAt === null ? 0 : Date.now() - startedAt
    cancelHold()
    if (heldMs < 3_000) {
      setOperationError(
        'Keep holding the confirmation control for three full seconds.',
      )
      return
    }
    if (!maintenance.challenge) return
    void run('confirm-maintenance', {
      token: maintenance.challenge,
      acknowledgedNonCriticalLoad: true,
      heldMs,
    })
  }

  const active = [
    'scheduled',
    'observing-load',
    'prepared',
    'running',
    'awaiting-mains',
    'recharging',
  ].includes(maintenance.phase)

  return (
    <div style={styles.page}>
      <div
        style={{
          display: 'flex',
          flexDirection: 'row',
          justifyContent: 'space-between',
          alignItems: 'flex-end',
        }}
      >
        <SectionTitle
          eyebrow="Maintenance"
          title="Calibration Lab"
          detail="A persisted, guarded workflow for self-tests and measured runtime checks."
        />
        <Tag tone={score === 100 ? 'lime' : score >= 50 ? 'amber' : 'red'}>
          {score}% READY
        </Tag>
      </div>
      <StatePanel
        tone="warning"
        title="Deep discharge consumes battery life"
        detail="Calibrate only after battery replacement or when the runtime estimate is materially inaccurate. Never attach critical workloads."
      />
      {operationError && (
        <StatePanel
          tone="critical"
          title="Maintenance request rejected"
          detail={operationError}
        />
      )}
      <div style={styles.row}>
        <Card style={{ flexGrow: 1 }}>
          <SectionTitle eyebrow="Readiness" title="Live safety envelope" />
          <div style={{ marginTop: 16 }}>
            <Progress
              value={score}
              color={score === 100 ? colors.lime : colors.amber}
            />
          </div>
          <DataRow
            label="Mains power"
            value={readiness[0] ? 'online' : 'blocked'}
          />
          <DataRow
            label="Communication"
            value={readiness[1] ? 'fresh' : 'stale'}
          />
          <DataRow
            label="Battery charge"
            value={
              readiness[2] ? 'full' : `${telemetry.batteryPercent ?? '—'}%`
            }
          />
          <DataRow
            label="Stable non-critical load"
            value={readiness[3] ? '30–40%' : `${telemetry.loadPercent ?? '—'}%`}
          />
        </Card>
        <Card style={{ flexGrow: 1 }}>
          <SectionTitle
            eyebrow="Self-test"
            title="Electronics & battery check"
            detail={`Last reported result: ${telemetry.selfTest ?? 'unknown'}`}
          />
          <text style={{ color: colors.muted, fontSize: 13, marginTop: 14 }}>
            {selfTest
              ? 'The agent verified an exclusive-device self-test driver for this model.'
              : 'This UPS reports prior self-test results, but no safe non-interactive command is verified. Use the front-panel procedure while keeping apcupsd online.'}
          </text>
          <div style={{ marginTop: 16 }}>
            <ActionButton
              label={selfTest ? 'Prepare self-test' : 'Self-test guidance only'}
              disabled={!selfTest || busy}
              onClick={() => void run('prepare-self-test')}
            />
          </div>
        </Card>
      </div>
      <Card>
        <div
          style={{
            display: 'flex',
            flexDirection: 'row',
            justifyContent: 'space-between',
            alignItems: 'flex-start',
          }}
        >
          <SectionTitle
            eyebrow="Runtime calibration"
            title={
              softwareCalibration
                ? 'Guarded automatic workflow'
                : 'Monitored manual workflow'
            }
            detail={capabilities.calibrationReason}
          />
          <Tag
            tone={
              active
                ? 'amber'
                : maintenance.phase === 'completed'
                  ? 'lime'
                  : 'cyan'
            }
          >
            {maintenance.phase.toUpperCase().replaceAll('-', ' ')}
          </Tag>
        </div>
        <text
          style={{
            color:
              maintenance.phase === 'completed' ? colors.lime : colors.amber,
            fontSize: 13,
            marginTop: 14,
          }}
        >
          {maintenance.message}
        </text>
        {active && (
          <div style={{ marginTop: 14 }}>
            <Progress value={maintenance.progress} color={colors.amber} />
          </div>
        )}
        {maintenance.phase === 'prepared' && (
          <div
            style={{
              display: 'flex',
              flexDirection: 'column',
              gap: 10,
              marginTop: 16,
            }}
          >
            <ActionButton
              label={
                acknowledged
                  ? '✓ Non-critical load confirmed'
                  : 'Confirm this is a non-critical load'
              }
              tone={acknowledged ? 'primary' : 'quiet'}
              onClick={() => setAcknowledged((value) => !value)}
            />
            <ActionButton
              label={
                holdReady
                  ? 'Release to confirm maintenance'
                  : confirming
                    ? 'Keep holding…'
                    : 'Hold 3 seconds to confirm'
              }
              disabled={!acknowledged || busy}
              onClick={() => {}}
              onMouseDown={startHold}
              onMouseUp={finishHold}
              onMouseLeave={cancelHold}
            />
          </div>
        )}
        {['idle', 'blocked', 'aborted', 'completed'].includes(
          maintenance.phase,
        ) && (
          <div
            style={{
              display: 'flex',
              flexDirection: 'row',
              gap: 10,
              marginTop: 16,
            }}
          >
            <ActionButton
              label="Begin one-minute load observation"
              disabled={preflight.phase !== 'preflight' || busy}
              onClick={() => void run('prepare-manual-calibration')}
            />
            <ActionButton
              label="Schedule for tomorrow"
              tone="quiet"
              disabled={preflight.phase !== 'preflight' || busy}
              onClick={() =>
                void run('schedule-manual-calibration', {
                  scheduledAt: Date.now() + 24 * 60 * 60 * 1_000,
                })
              }
            />
          </div>
        )}
        {active && (
          <div style={{ marginTop: 16 }}>
            <ActionButton
              label="Abort & return to safe guidance"
              tone="danger"
              disabled={busy || confirming}
              onClick={() =>
                void run('abort-maintenance', {
                  reason: 'requested from Calibration Lab',
                })
              }
            />
          </div>
        )}
        {!softwareCalibration && maintenance.phase === 'idle' && (
          <div
            style={{
              display: 'flex',
              flexDirection: 'column',
              gap: 9,
              marginTop: 16,
            }}
          >
            <DataRow label="1" value="Stabilize a 30–40% non-critical load" />
            <DataRow
              label="2"
              value="Pass the one-minute observation and Polkit confirmation"
            />
            <DataRow
              label="3"
              value="Disconnect and reconnect mains only when prompted"
            />
            <DataRow
              label="4"
              value="Wait for Gridwatch to verify a 99% recharge"
            />
            <text style={{ color: colors.red, fontSize: 12, marginTop: 8 }}>
              Gridwatch monitors this manual path. It does not stop apcupsd,
              access USB, or switch mains power on this model.
            </text>
          </div>
        )}
      </Card>
      {(maintenance.baselineRuntimeMinutes !== null ||
        maintenance.resultRuntimeMinutes !== null) && (
        <Card>
          <SectionTitle eyebrow="Result" title="Runtime estimate comparison" />
          <DataRow
            label="Before workflow"
            value={`${maintenance.baselineRuntimeMinutes?.toFixed(1) ?? '—'} min`}
          />
          <DataRow
            label="After full recharge"
            value={`${maintenance.resultRuntimeMinutes?.toFixed(1) ?? '—'} min`}
          />
          <DataRow
            label="Cooldown"
            value={
              maintenance.cooldownUntil
                ? new Date(maintenance.cooldownUntil).toLocaleDateString()
                : 'not active'
            }
          />
        </Card>
      )}
    </div>
  )
}

function idleMaintenance(): MaintenanceStatus {
  return {
    phase: 'idle',
    operation: null,
    progress: 0,
    message: 'No maintenance operation is active.',
    scheduledAt: null,
    stableSince: null,
    preparedAt: null,
    challengeExpiresAt: null,
    startedAt: null,
    updatedAt: Date.now(),
    cooldownUntil: null,
    baselineRuntimeMinutes: null,
    resultRuntimeMinutes: null,
    seenOnBattery: false,
  }
}
