import type { ReactNode } from 'react'
import { capabilityProbe, type UpsTelemetry, type Alert } from '../domain/ups'
import type { HistoryPoint } from '../storage/history'
import { colors, styles } from '../app/theme'
import { Card, Label, Metric, Progress, SectionTitle } from '../ui/primitives'
import { Sparkline } from '../ui/chart'

const fmt = (v: number | null, digits = 1) =>
  v === null ? '—' : v.toFixed(digits)
export function Overview({
  telemetry,
  history,
  alerts,
}: {
  telemetry: UpsTelemetry
  history: HistoryPoint[]
  alerts: Alert[]
}) {
  const statusColor =
    telemetry.status === 'online'
      ? colors.lime
      : telemetry.status === 'on-battery'
        ? colors.amber
        : colors.red
  return (
    <div style={styles.page}>
      <div
        style={{
          display: 'flex',
          flexDirection: 'row',
          justifyContent: 'space-between',
          alignItems: 'flex-end',
        }}
      >
        <div>
          <text style={{ color: colors.cyan, fontSize: 12 }}>
            GRIDWATCH / ELECTRIC OBSERVATORY
          </text>
          <text
            style={{
              color: colors.text,
              fontSize: 34,
              fontWeight: 800,
              marginTop: 7,
            }}
          >
            Power, made visible.
          </text>
          <text style={{ color: colors.muted, fontSize: 14, marginTop: 6 }}>
            {telemetry.model} ·{' '}
            {telemetry.source === 'demo' ? 'simulation' : 'apcupsd'}
          </text>
        </div>
        <div
          style={{
            display: 'flex',
            flexDirection: 'row',
            gap: 8,
            alignItems: 'center',
          }}
        >
          <div
            style={{
              width: 10,
              height: 10,
              borderRadius: 5,
              background: statusColor,
            }}
          />
          <text style={{ color: statusColor, fontSize: 13, fontWeight: 700 }}>
            {telemetry.status.replace('-', ' ').toUpperCase()}
          </text>
        </div>
      </div>
      {telemetry.status === 'on-battery' && (
        <Card style={{ background: '#342919', borderColor: colors.amber }}>
          <text style={{ color: colors.amber, fontSize: 15, fontWeight: 700 }}>
            ⚡ Grid interruption detected
          </text>
          <text style={{ color: '#e6c899', fontSize: 13, marginTop: 5 }}>
            Gridwatch is watching the discharge curve and will notify you before
            policy thresholds.
          </text>
        </Card>
      )}
      <div style={{ display: 'flex', flexDirection: 'row', gap: 14 }}>
        <Card
          style={{
            flexGrow: 2,
            background: {
              type: 'linear-gradient',
              angle: 135,
              stops: [
                { color: '#0c252c', position: 0 },
                { color: '#152e25', position: 1 },
              ],
            },
          }}
        >
          <Label>ENERGY CORE</Label>
          <div
            style={{
              display: 'flex',
              flexDirection: 'row',
              alignItems: 'center',
              gap: 26,
              marginTop: 15,
            }}
          >
            <div
              style={{
                width: 132,
                height: 132,
                borderRadius: 66,
                borderWidth: 2,
                borderColor: statusColor,
                background: '#0a171b',
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                justifyContent: 'center',
              }}
            >
              <text
                style={{ color: statusColor, fontSize: 35, fontWeight: 800 }}
              >
                {fmt(telemetry.batteryPercent, 0)}%
              </text>
              <text style={{ color: colors.muted, fontSize: 11 }}>CHARGE</text>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 7 }}>
              <text
                style={{ color: colors.text, fontSize: 20, fontWeight: 700 }}
              >
                {fmt(telemetry.runtimeMinutes)} min remaining
              </text>
              <text style={{ color: colors.muted, fontSize: 13 }}>
                A dynamic estimate based on battery and load.
              </text>
              <Progress
                value={telemetry.batteryPercent ?? 0}
                color={statusColor}
              />
            </div>
          </div>
        </Card>
        <Card style={{ flexGrow: 1 }}>
          <Label>POWER DNA</Label>
          <div
            style={{
              display: 'flex',
              flexDirection: 'column',
              gap: 15,
              marginTop: 15,
            }}
          >
            <Metric
              label="INPUT"
              value={fmt(telemetry.lineVoltage)}
              suffix="V"
            />
            <Metric
              label="LOAD"
              value={fmt(telemetry.loadPercent, 0)}
              suffix="%"
            />
          </div>
        </Card>
      </div>
      <div style={{ display: 'flex', flexDirection: 'row', gap: 14 }}>
        <Metric
          label="BATTERY VOLTAGE"
          value={fmt(telemetry.batteryVoltage)}
          suffix="VDC"
        />
        <Metric
          label="NOMINAL POWER"
          value={fmt(telemetry.nominalPowerWatts, 0)}
          suffix="W"
        />
        <Metric
          label="TRANSFERS"
          value={fmt(telemetry.transfers, 0)}
          suffix="events"
        />
        <Metric
          label="LAST SAMPLE"
          value={new Date(telemetry.timestamp).toLocaleTimeString([], {
            hour: '2-digit',
            minute: '2-digit',
          })}
        />
      </div>
      <Card>
        <SectionTitle
          eyebrow="Load pulse"
          title="The last 24 hours"
          detail="A quiet load is a healthy load. The agent stores high-resolution changes, then compresses older history."
        />
        <Sparkline points={history} />
      </Card>
      {alerts.length > 0 && (
        <Card>
          <SectionTitle
            eyebrow="Signal inbox"
            title={`${alerts.length} active signal${alerts.length === 1 ? '' : 's'}`}
          />
          {alerts.slice(0, 3).map((a) => (
            <div
              key={a.id}
              style={{
                display: 'flex',
                flexDirection: 'row',
                gap: 10,
                paddingTop: 12,
              }}
            >
              <text
                style={{
                  color: a.severity === 'critical' ? colors.red : colors.amber,
                }}
              >
                ●
              </text>
              <div>
                <text
                  style={{ color: colors.text, fontSize: 14, fontWeight: 700 }}
                >
                  {a.title}
                </text>
                <text
                  style={{ color: colors.muted, fontSize: 12, marginTop: 3 }}
                >
                  {a.detail}
                </text>
              </div>
            </div>
          ))}
        </Card>
      )}
    </div>
  )
}

export function InfoView({
  telemetry,
  title,
  eyebrow,
  children,
}: {
  telemetry: UpsTelemetry
  title: string
  eyebrow: string
  children?: ReactNode
}) {
  const caps = capabilityProbe(telemetry)
  return (
    <div style={styles.page}>
      <SectionTitle eyebrow={eyebrow} title={title} detail={telemetry.model} />
      <Card>
        <text style={{ color: colors.text, fontSize: 16, fontWeight: 700 }}>
          Device identity
        </text>
        <div
          style={{
            display: 'flex',
            flexDirection: 'column',
            gap: 8,
            marginTop: 12,
          }}
        >
          <text style={{ color: colors.muted, fontSize: 13 }}>
            Serial {telemetry.serial ?? 'not reported'}
          </text>
          <text style={{ color: colors.muted, fontSize: 13 }}>
            Firmware {telemetry.firmware ?? 'not reported'}
          </text>
          <text style={{ color: colors.muted, fontSize: 13 }}>
            Battery date {telemetry.batteryDate ?? 'not reported'}
          </text>
        </div>
      </Card>
      <Card>
        <text style={{ color: colors.text, fontSize: 16, fontWeight: 700 }}>
          Capabilities
        </text>
        <text style={{ color: colors.muted, fontSize: 13, marginTop: 8 }}>
          {caps.supported.length
            ? caps.supported.join(' · ')
            : 'Read-only telemetry only'}
        </text>
        <text style={{ color: colors.muted, fontSize: 12, marginTop: 5 }}>
          {caps.calibrationReason}
        </text>
      </Card>
      {children}
    </div>
  )
}
