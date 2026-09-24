import type { ReactNode } from 'react'
import { colors } from '../app/theme'
import { Card } from '../ui/primitives'

export function ActionButton({
  label,
  onClick,
  onMouseDown,
  onMouseUp,
  onMouseLeave,
  disabled = false,
  tone = 'primary',
}: {
  label: string
  onClick: () => void
  onMouseDown?: () => void
  onMouseUp?: () => void
  onMouseLeave?: () => void
  disabled?: boolean
  tone?: 'primary' | 'quiet' | 'danger'
}) {
  const background =
    tone === 'danger' ? '#542630' : tone === 'quiet' ? '#173038' : colors.cyan
  const color = tone === 'primary' ? '#05201f' : colors.text
  return (
    <div
      aria-label={label}
      onClick={() => !disabled && onClick()}
      onMouseDown={() => !disabled && onMouseDown?.()}
      onMouseUp={() => !disabled && onMouseUp?.()}
      onMouseLeave={() => !disabled && onMouseLeave?.()}
      style={{
        paddingTop: 10,
        paddingBottom: 10,
        paddingLeft: 16,
        paddingRight: 16,
        borderRadius: 10,
        background,
        color,
        fontSize: 13,
        fontWeight: 700,
        opacity: disabled ? 0.4 : 1,
        cursor: disabled ? 'default' : 'pointer',
        hover: disabled ? undefined : { opacity: 0.86 },
      }}
    >
      {label}
    </div>
  )
}

export function DataRow({
  label,
  value,
  note,
}: {
  label: string
  value: ReactNode
  note?: string
}) {
  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
        gap: 14,
        paddingTop: 11,
        paddingBottom: 11,
        borderBottomWidth: 1,
        borderColor: colors.line,
      }}
    >
      <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
        <text style={{ color: colors.text, fontSize: 13 }}>{label}</text>
        {note && (
          <text style={{ color: colors.muted, fontSize: 11 }}>{note}</text>
        )}
      </div>
      <text style={{ color: colors.cyan, fontSize: 13, fontWeight: 700 }}>
        {value}
      </text>
    </div>
  )
}

export function StatePanel({
  title,
  detail,
  tone = 'neutral',
}: {
  title: string
  detail: string
  tone?: 'neutral' | 'warning' | 'critical' | 'success'
}) {
  const accent =
    tone === 'critical'
      ? colors.red
      : tone === 'warning'
        ? colors.amber
        : tone === 'success'
          ? colors.lime
          : colors.cyan
  return (
    <Card style={{ borderColor: accent, background: `${accent}12` }}>
      <text style={{ color: accent, fontSize: 15, fontWeight: 700 }}>
        {title}
      </text>
      <text style={{ color: colors.muted, fontSize: 13, marginTop: 6 }}>
        {detail}
      </text>
    </Card>
  )
}

export function NumericField({
  label,
  value,
  suffix,
  onChange,
  disabled = false,
}: {
  label: string
  value: number
  suffix: string
  onChange: (value: number) => void
  disabled?: boolean
}) {
  return (
    <div
      style={{ display: 'flex', flexDirection: 'column', gap: 7, flexGrow: 1 }}
    >
      <text style={{ color: colors.muted, fontSize: 12 }}>{label}</text>
      <div
        style={{
          display: 'flex',
          flexDirection: 'row',
          alignItems: 'center',
          background: colors.panelRaised,
          borderWidth: 1,
          borderColor: colors.line,
          borderRadius: 10,
          paddingLeft: 12,
          paddingRight: 12,
          opacity: disabled ? 0.55 : 1,
        }}
      >
        <input
          value={String(value)}
          onChange={(event) => {
            if (disabled) return
            const parsed = Number(event.value)
            if (Number.isFinite(parsed)) onChange(parsed)
          }}
          style={{
            flexGrow: 1,
            color: colors.text,
            fontSize: 15,
            paddingTop: 10,
            paddingBottom: 10,
          }}
        />
        <text style={{ color: colors.muted, fontSize: 12 }}>{suffix}</text>
      </div>
    </div>
  )
}

export function Tag({
  children,
  tone = 'cyan',
}: {
  children: ReactNode
  tone?: 'cyan' | 'lime' | 'amber' | 'red'
}) {
  const color = colors[tone]
  return (
    <text
      style={{
        color,
        background: `${color}16`,
        borderRadius: 8,
        paddingTop: 5,
        paddingBottom: 5,
        paddingLeft: 8,
        paddingRight: 8,
        fontSize: 11,
        fontWeight: 700,
      }}
    >
      {children}
    </text>
  )
}
