import { colors } from '../app/theme'
import type { HistoryPoint } from '../storage/history'
export function Sparkline({
  points,
  field = 'load',
  color = colors.cyan,
}: {
  points: HistoryPoint[]
  field?: 'load' | 'battery' | 'runtime'
  color?: string
}) {
  const values = points.map((p) => p[field] ?? 0)
  const max = Math.max(...values, 1)
  const min = Math.min(...values, 0)
  const width = 420
  const height = 90
  const path = values
    .map(
      (v, i) =>
        `${i ? 'L' : 'M'} ${((i / Math.max(values.length - 1, 1)) * width).toFixed(1)} ${(height - ((v - min) / Math.max(max - min, 1)) * (height - 8) - 4).toFixed(1)}`,
    )
    .join(' ')
  return (
    <svg
      source={`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} ${height}"><path d="${path}" fill="none" stroke="${color}" stroke-width="3" stroke-linecap="round"/><path d="${path} L ${width} ${height} L 0 ${height} Z" fill="${color}" opacity=".10"/></svg>`}
      style={{ width: '100%', height }}
      aria-label={`${field} history`}
    />
  )
}
