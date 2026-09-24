import type { ReactNode } from 'react'
import { colors, styles } from '../app/theme'
export function Card({
  children,
  style,
}: {
  children: ReactNode
  style?: Record<string, unknown>
}) {
  return <div style={{ ...styles.card, ...style }}>{children}</div>
}
export function Label({ children }: { children: ReactNode }) {
  return <text style={styles.label}>{children}</text>
}
export function Metric({
  label,
  value,
  suffix,
}: {
  label: string
  value: ReactNode
  suffix?: string
}) {
  return (
    <Card style={{ flexGrow: 1 }}>
      <Label>{label}</Label>
      <div
        style={{
          display: 'flex',
          flexDirection: 'row',
          alignItems: 'baseline',
          gap: 5,
          marginTop: 7,
        }}
      >
        <text style={styles.value}>{value}</text>
        {suffix && (
          <text style={{ color: colors.muted, fontSize: 13 }}>{suffix}</text>
        )}
      </div>
    </Card>
  )
}
export function SectionTitle({
  eyebrow,
  title,
  detail,
}: {
  eyebrow: string
  title: string
  detail?: string
}) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 5 }}>
      <text style={{ ...styles.label, color: colors.cyan }}>
        {eyebrow.toUpperCase()}
      </text>
      <text style={{ color: colors.text, fontSize: 22, fontWeight: 700 }}>
        {title}
      </text>
      {detail && (
        <text style={{ color: colors.muted, fontSize: 13 }}>{detail}</text>
      )}
    </div>
  )
}
export function Progress({
  value,
  color = colors.cyan,
}: {
  value: number
  color?: string
}) {
  return (
    <div
      style={{
        height: 8,
        background: '#183137',
        borderRadius: 4,
        overflow: 'hidden',
      }}
    >
      <div
        style={{
          height: 8,
          width: `${Math.max(0, Math.min(100, value))}%`,
          background: color,
          borderRadius: 4,
        }}
      />
    </div>
  )
}
