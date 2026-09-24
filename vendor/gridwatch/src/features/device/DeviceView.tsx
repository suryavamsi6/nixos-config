import { colors, styles } from '../../app/theme'
import { capabilityProbe, type UpsTelemetry } from '../../domain/ups'
import { Card, SectionTitle } from '../../ui/primitives'
import { DataRow, StatePanel, Tag } from '../shared'

export function DeviceView({ telemetry }: { telemetry: UpsTelemetry }) {
  const capabilities = capabilityProbe(telemetry)
  const measured = [
    ['Line voltage', unit(telemetry.lineVoltage, 'V')],
    ['Battery voltage', unit(telemetry.batteryVoltage, 'V DC')],
    ['Battery charge', unit(telemetry.batteryPercent, '%')],
    ['Load', unit(telemetry.loadPercent, '%')],
  ]
  const estimated = [
    ['Remaining runtime', unit(telemetry.runtimeMinutes, 'min')],
    ['Nominal power ceiling', unit(telemetry.nominalPowerWatts, 'W')],
  ]
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
        <SectionTitle
          eyebrow="Hardware atlas"
          title={telemetry.model}
          detail="Device identity, firmware, electrical envelope, and verified capabilities."
        />
        <Tag
          tone={
            telemetry.status === 'online'
              ? 'lime'
              : telemetry.status === 'offline'
                ? 'red'
                : 'amber'
          }
        >
          {telemetry.status.toUpperCase()}
        </Tag>
      </div>
      {telemetry.stale && (
        <StatePanel
          tone="warning"
          title="Using stale device data"
          detail="Values below are the last known readings and must not be used to authorize maintenance."
        />
      )}
      <div style={styles.row}>
        <Card style={{ flexGrow: 1 }}>
          <SectionTitle eyebrow="Identity" title="Nameplate" />
          <DataRow label="Model" value={telemetry.model} />
          <DataRow label="Serial" value={telemetry.serial ?? 'not reported'} />
          <DataRow
            label="Firmware"
            value={telemetry.firmware ?? 'not reported'}
          />
          <DataRow
            label="Battery date"
            value={telemetry.batteryDate ?? 'not reported'}
          />
        </Card>
        <Card style={{ flexGrow: 1 }}>
          <SectionTitle eyebrow="Service record" title="Operating counters" />
          <DataRow
            label="Transfers"
            value={telemetry.transfers?.toFixed(0) ?? '—'}
          />
          <DataRow
            label="Last transfer"
            value={telemetry.lastTransfer ?? 'not reported'}
          />
          <DataRow
            label="Time on battery"
            value={unit(telemetry.onBatterySeconds, 's')}
          />
          <DataRow
            label="Last self-test result"
            value={telemetry.selfTest ?? 'not reported'}
            note="A reported result does not prove remote test support."
          />
        </Card>
      </div>
      <div style={styles.row}>
        <Card style={{ flexGrow: 1 }}>
          <SectionTitle
            eyebrow="Measured"
            title="Direct telemetry"
            detail="Reported by the UPS through apcupsd."
          />
          {measured.map(([label, value]) => (
            <DataRow key={label} label={label} value={value} />
          ))}
        </Card>
        <Card style={{ flexGrow: 1 }}>
          <SectionTitle
            eyebrow="Estimated"
            title="Derived & nominal"
            detail="Planning signals, not laboratory measurements."
          />
          {estimated.map(([label, value]) => (
            <DataRow key={label} label={label} value={value} />
          ))}
          <DataRow
            label="Nominal battery"
            value={unit(telemetry.nominalBatteryVoltage, 'V')}
          />
        </Card>
      </div>
      <Card>
        <SectionTitle
          eyebrow="Capability firewall"
          title="Controls stay hidden until proven safe"
        />
        <text style={{ color: colors.muted, fontSize: 13, marginTop: 10 }}>
          {capabilities.calibrationReason}
        </text>
        <text style={{ color: colors.text, fontSize: 13, marginTop: 8 }}>
          Verified mutation capabilities:{' '}
          {capabilities.supported.length
            ? capabilities.supported.join(' · ')
            : 'none'}
        </text>
      </Card>
    </div>
  )
}

function unit(value: number | null, suffix: string): string {
  return value === null ? '—' : `${value.toFixed(1)} ${suffix}`
}
