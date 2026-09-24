import { DEFAULT_POLICY, validatePolicy } from './policy'
import type { GridwatchSettings } from './ups'

export const DEFAULT_SETTINGS: GridwatchSettings = {
  ...DEFAULT_POLICY,
  energyRate: 0.2,
  rawRetentionHours: 24,
  minuteRetentionDays: 90,
  notifyOnBattery: true,
  notifyCritical: true,
  silentHoursStart: 22,
  silentHoursEnd: 7,
  selfTestCadenceDays: 14,
  shutdownAction: 'shutdown',
}

export interface SettingsState {
  effective: GridwatchSettings
  draft: GridwatchSettings
  dirty: boolean
  saving: boolean
  error: string | null
}

export function validateSettings(
  input: Partial<GridwatchSettings>,
): GridwatchSettings {
  const shutdown = validatePolicy({ ...DEFAULT_POLICY, ...input })
  return {
    ...shutdown,
    energyRate: bounded(
      input.energyRate,
      DEFAULT_SETTINGS.energyRate,
      0,
      10,
      3,
    ),
    rawRetentionHours: bounded(
      input.rawRetentionHours,
      DEFAULT_SETTINGS.rawRetentionHours,
      1,
      168,
    ),
    minuteRetentionDays: bounded(
      input.minuteRetentionDays,
      DEFAULT_SETTINGS.minuteRetentionDays,
      1,
      3650,
    ),
    notifyOnBattery: input.notifyOnBattery ?? DEFAULT_SETTINGS.notifyOnBattery,
    notifyCritical: input.notifyCritical ?? DEFAULT_SETTINGS.notifyCritical,
    silentHoursStart: bounded(
      input.silentHoursStart,
      DEFAULT_SETTINGS.silentHoursStart,
      0,
      23,
    ),
    silentHoursEnd: bounded(
      input.silentHoursEnd,
      DEFAULT_SETTINGS.silentHoursEnd,
      0,
      23,
    ),
    selfTestCadenceDays: bounded(
      input.selfTestCadenceDays,
      DEFAULT_SETTINGS.selfTestCadenceDays,
      0,
      365,
    ),
    shutdownAction:
      input.shutdownAction === 'hibernate' ? 'hibernate' : 'shutdown',
  }
}

export function initialSettings(
  effective: Partial<GridwatchSettings> = {},
): SettingsState {
  const value = validateSettings({ ...DEFAULT_SETTINGS, ...effective })
  return {
    effective: value,
    draft: value,
    dirty: false,
    saving: false,
    error: null,
  }
}

export function editSettings(
  state: SettingsState,
  patch: Partial<GridwatchSettings>,
): SettingsState {
  const draft = validateSettings({ ...state.draft, ...patch })
  return {
    ...state,
    draft,
    dirty: JSON.stringify(draft) !== JSON.stringify(state.effective),
    error: null,
  }
}

export function settingsSaved(
  state: SettingsState,
  effective: GridwatchSettings = state.draft,
): SettingsState {
  const value = validateSettings(effective)
  return {
    ...state,
    effective: value,
    draft: value,
    dirty: false,
    saving: false,
    error: null,
  }
}

export function settingsFailed(
  state: SettingsState,
  error: string,
): SettingsState {
  return { ...state, saving: false, error }
}

function bounded(
  value: number | undefined,
  fallback: number,
  minimum: number,
  maximum: number,
  digits = 0,
): number {
  const safe =
    typeof value === 'number' && Number.isFinite(value) ? value : fallback
  const factor = 10 ** digits
  return Math.max(
    minimum,
    Math.min(maximum, Math.round(safe * factor) / factor),
  )
}
