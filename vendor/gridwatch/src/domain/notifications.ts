import type { Alert, GridwatchSettings } from './ups'

export function shouldNotifyDesktop(
  alert: Alert,
  settings: GridwatchSettings,
  now = new Date(),
): boolean {
  if (alert.acknowledged || alert.severity === 'info') return false
  if (alert.severity === 'critical') return settings.notifyCritical
  if (!settings.notifyOnBattery) return false
  return !isSilentHour(
    now.getHours(),
    settings.silentHoursStart,
    settings.silentHoursEnd,
  )
}

export function isSilentHour(
  hour: number,
  start: number,
  end: number,
): boolean {
  if (start === end) return false
  if (start < end) return hour >= start && hour < end
  return hour >= start || hour < end
}
