import type { CalibrationPhase, UpsTelemetry } from './ups'

export interface CalibrationState {
  phase: CalibrationPhase
  progress: number
  message: string
  scheduledAt: number | null
  startedAt: number | null
}

export const initialCalibration: CalibrationState = {
  phase: 'idle',
  progress: 0,
  message: 'No calibration scheduled.',
  scheduledAt: null,
  startedAt: null,
}

export function preflightCalibration(t: UpsTelemetry): CalibrationState {
  if (t.stale)
    return {
      ...initialCalibration,
      phase: 'blocked',
      message: 'Fresh UPS telemetry is required before maintenance.',
    }
  if (t.status !== 'online')
    return {
      ...initialCalibration,
      phase: 'blocked',
      message: 'UPS must be online before calibration.',
    }
  if ((t.batteryPercent ?? 0) < 100)
    return {
      ...initialCalibration,
      phase: 'blocked',
      message: 'Battery must be fully charged.',
    }
  if ((t.loadPercent ?? 0) < 30)
    return {
      ...initialCalibration,
      phase: 'blocked',
      message: 'Attach a stable, non-critical load of at least 30%.',
    }
  if ((t.loadPercent ?? 100) > 40)
    return {
      ...initialCalibration,
      phase: 'blocked',
      message: 'Reduce the non-critical load to 40% or less.',
    }
  return {
    ...initialCalibration,
    phase: 'preflight',
    message: 'Preconditions passed. Hold to confirm the deep-discharge test.',
  }
}

export function advanceCalibration(
  state: CalibrationState,
  telemetry: UpsTelemetry,
): CalibrationState {
  if (state.phase === 'running') {
    if (telemetry.status === 'offline')
      return {
        ...state,
        phase: 'aborted',
        message: 'Calibration aborted because communication was lost.',
      }
    if (telemetry.batteryPercent !== null)
      return {
        ...state,
        progress: Math.max(0, Math.min(100, 100 - telemetry.batteryPercent)),
        message: `Discharging — ${telemetry.batteryPercent.toFixed(0)}% remaining.`,
      }
  }
  if (
    state.phase === 'recharging' &&
    telemetry.batteryPercent !== null &&
    telemetry.batteryPercent >= 99
  )
    return {
      ...state,
      phase: 'completed',
      progress: 100,
      message: 'Calibration complete; battery is charged.',
    }
  return state
}
