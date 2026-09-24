import type { UpsTelemetry } from '../domain/ups'

export interface HistoryPoint {
  timestamp: number
  load: number | null
  battery: number | null
  runtime: number | null
  line: number | null
}
export function point(t: UpsTelemetry): HistoryPoint {
  return {
    timestamp: t.timestamp,
    load: t.loadPercent,
    battery: t.batteryPercent,
    runtime: t.runtimeMinutes,
    line: t.lineVoltage,
  }
}
export function downsample(
  points: HistoryPoint[],
  maxPoints: number,
): HistoryPoint[] {
  if (points.length <= maxPoints) return points
  const stride = (points.length - 1) / (maxPoints - 1)
  return Array.from(
    { length: maxPoints },
    (_, index) => points[Math.round(index * stride)],
  )
}
