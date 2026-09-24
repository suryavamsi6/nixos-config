export type GridState =
  | 'online'
  | 'on-battery'
  | 'low-battery'
  | 'overload'
  | 'replace-battery'
  | 'offline'
  | 'unknown'

export type Capability =
  | 'self-test'
  | 'runtime-calibration'
  | 'sensitivity'
  | 'transfer-voltage'
  | 'alarm-control'

export interface UpsTelemetry {
  timestamp: number
  model: string
  serial: string | null
  firmware: string | null
  status: GridState
  rawStatus: string
  lineVoltage: number | null
  loadPercent: number | null
  batteryPercent: number | null
  runtimeMinutes: number | null
  batteryVoltage: number | null
  nominalPowerWatts: number | null
  nominalBatteryVoltage: number | null
  transfers: number | null
  lastTransfer: string | null
  onBatterySeconds: number | null
  batteryDate: string | null
  selfTest: string | null
  sensitivity: string | null
  lowTransferVoltage: number | null
  highTransferVoltage: number | null
  stale: boolean
  source: 'apcupsd' | 'demo'
  capabilities: Capability[]
  capabilityReason: string
  maintenance: MaintenanceStatus | null
}

export interface UpsCapabilities {
  supported: Capability[]
  calibrationReason: string
}

export interface ShutdownPolicy {
  batteryLevel: number
  minutes: number
}

export interface GridwatchSettings extends ShutdownPolicy {
  energyRate: number
  rawRetentionHours: number
  minuteRetentionDays: number
  notifyOnBattery: boolean
  notifyCritical: boolean
  silentHoursStart: number
  silentHoursEnd: number
  selfTestCadenceDays: number
  shutdownAction: 'shutdown' | 'hibernate'
}

export interface Alert {
  id: string
  severity: 'info' | 'warning' | 'critical'
  title: string
  detail: string
  at: number
  acknowledged: boolean
}

export type CalibrationPhase =
  | 'idle'
  | 'scheduled'
  | 'preflight'
  | 'observing-load'
  | 'prepared'
  | 'running'
  | 'awaiting-mains'
  | 'recharging'
  | 'completed'
  | 'aborted'
  | 'blocked'

export interface MaintenanceStatus {
  phase: CalibrationPhase
  operation: string | null
  progress: number
  message: string
  scheduledAt: number | null
  stableSince: number | null
  preparedAt: number | null
  challengeExpiresAt: number | null
  startedAt: number | null
  updatedAt: number
  cooldownUntil: number | null
  baselineRuntimeMinutes: number | null
  resultRuntimeMinutes: number | null
  seenOnBattery: boolean
  challenge?: string
}

export function capabilityProbe(t: UpsTelemetry): UpsCapabilities {
  return {
    supported: t.capabilities,
    calibrationReason: t.capabilityReason,
  }
}

export function normalizeStatus(raw: string): GridState {
  const status = raw.toUpperCase()
  if (status.includes('COMMLOST') || status.includes('OFF')) return 'offline'
  if (status.includes('OVER')) return 'overload'
  if (status.includes('RB')) return 'replace-battery'
  if (status.includes('LB')) return 'low-battery'
  if (status.includes('OB')) return 'on-battery'
  if (status.includes('OL') || status.includes('ONLINE')) return 'online'
  return 'unknown'
}

export function minutesFromApc(value: string | undefined): number | null {
  if (!value) return null
  const n = Number.parseFloat(value.replace(',', '.'))
  return Number.isFinite(n) ? n : null
}

export function numberFromApc(value: string | undefined): number | null {
  if (!value) return null
  const n = Number.parseFloat(value.replace(',', '.'))
  return Number.isFinite(n) ? n : null
}

export function makeAlert(
  t: UpsTelemetry,
  previous?: UpsTelemetry,
): Alert | null {
  if (t.status === 'offline')
    return {
      id: `offline-${t.timestamp}`,
      severity: 'critical',
      title: 'UPS communication lost',
      detail: 'Gridwatch cannot read the UPS through apcupsd.',
      at: t.timestamp,
      acknowledged: false,
    }
  if (t.status === 'on-battery' && previous?.status === 'online')
    return {
      id: `battery-${t.timestamp}`,
      severity: 'warning',
      title: 'Running on battery',
      detail: `Estimated runtime is ${t.runtimeMinutes?.toFixed(1) ?? 'unknown'} minutes.`,
      at: t.timestamp,
      acknowledged: false,
    }
  if (t.status === 'low-battery')
    return {
      id: `low-${t.timestamp}`,
      severity: 'critical',
      title: 'Low battery',
      detail: 'Graceful shutdown policy may trigger soon.',
      at: t.timestamp,
      acknowledged: false,
    }
  if (t.status === 'replace-battery')
    return {
      id: `replace-${t.timestamp}`,
      severity: 'critical',
      title: 'Battery replacement recommended',
      detail: 'The UPS is reporting a replace-battery condition.',
      at: t.timestamp,
      acknowledged: false,
    }
  return null
}
