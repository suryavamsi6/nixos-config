import type { ShutdownPolicy } from './ups'

export const DEFAULT_POLICY: ShutdownPolicy = { batteryLevel: 50, minutes: 5 }
export function validatePolicy(input: Partial<ShutdownPolicy>): ShutdownPolicy {
  const batteryLevel =
    typeof input.batteryLevel === 'number' &&
    Number.isFinite(input.batteryLevel)
      ? Math.round(input.batteryLevel)
      : DEFAULT_POLICY.batteryLevel
  const minutes =
    typeof input.minutes === 'number' && Number.isFinite(input.minutes)
      ? Math.round(input.minutes)
      : DEFAULT_POLICY.minutes
  return {
    batteryLevel: Math.max(5, Math.min(90, batteryLevel)),
    minutes: Math.max(1, Math.min(60, minutes)),
  }
}
