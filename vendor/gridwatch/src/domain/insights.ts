import type { HistoryPoint } from '../storage/history'

export interface HistoryInsights {
  averageLoadPercent: number | null
  peakLoadPercent: number | null
  minimumLineVoltage: number | null
  maximumLineVoltage: number | null
  estimatedEnergyKwh: number | null
  estimatedCost: number | null
}

export function historyInsights(
  points: HistoryPoint[],
  nominalPowerWatts: number | null,
  energyRate: number,
): HistoryInsights {
  const load = points.flatMap((item) => (item.load === null ? [] : [item.load]))
  const line = points.flatMap((item) => (item.line === null ? [] : [item.line]))
  let wattHours = 0
  if (nominalPowerWatts !== null) {
    for (let index = 1; index < points.length; index += 1) {
      const previous = points[index - 1]
      const current = points[index]
      if (previous.load === null || current.load === null) continue
      const hours = Math.max(
        0,
        Math.min(1, (current.timestamp - previous.timestamp) / 3_600_000),
      )
      wattHours +=
        nominalPowerWatts * ((previous.load + current.load) / 2 / 100) * hours
    }
  }
  const estimatedEnergyKwh =
    nominalPowerWatts === null ? null : wattHours / 1000
  return {
    averageLoadPercent: average(load),
    peakLoadPercent: load.length ? Math.max(...load) : null,
    minimumLineVoltage: line.length ? Math.min(...line) : null,
    maximumLineVoltage: line.length ? Math.max(...line) : null,
    estimatedEnergyKwh,
    estimatedCost:
      estimatedEnergyKwh === null ? null : estimatedEnergyKwh * energyRate,
  }
}

function average(values: number[]): number | null {
  if (!values.length) return null
  return values.reduce((total, value) => total + value, 0) / values.length
}
