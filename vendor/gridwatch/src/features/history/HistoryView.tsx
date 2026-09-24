import { colors, styles } from '../../app/theme'
import { historyInsights } from '../../domain/insights'
import type { UpsTelemetry } from '../../domain/ups'
import type { HistoryPoint } from '../../storage/history'
import { Sparkline } from '../../ui/chart'
import { Card, Metric, SectionTitle } from '../../ui/primitives'
import { StatePanel, Tag } from '../shared'

export function HistoryView({
  telemetry,
  history,
  energyRate = 0.2,
}: {
  telemetry: UpsTelemetry
  history: HistoryPoint[]
  energyRate?: number
}) {
  const insights = historyInsights(
    history,
    telemetry.nominalPowerWatts,
    energyRate,
  )
  if (telemetry.status === 'offline' && history.length === 0)
    return (
      <div style={styles.page}>
        <SectionTitle eyebrow="Power archive" title="History" />
        <StatePanel
          tone="critical"
          title="History is unavailable"
          detail="The local agent is offline and no persisted samples could be loaded. Gridwatch will resume the archive automatically when the agent returns."
        />
      </div>
    )
  return (
    <div style={styles.page}>
      <div
        style={{
          display: 'flex',
          flexDirection: 'row',
          justifyContent: 'space-between',
        }}
      >
        <SectionTitle
          eyebrow="Power archive"
          title="24-hour field record"
          detail="One-minute rollups from the agent-owned SQLite archive."
        />
        <Tag tone={telemetry.stale ? 'amber' : 'lime'}>
          {telemetry.stale ? 'STALE DATA' : `${history.length} SAMPLES`}
        </Tag>
      </div>
      {history.length === 0 ? (
        <StatePanel
          title="Building the first trace"
          detail="The agent is connected. Trend cards will appear after the first persisted samples arrive."
        />
      ) : (
        <>
          <div style={styles.row}>
            <Metric
              label="AVERAGE LOAD"
              value={format(insights.averageLoadPercent)}
              suffix="%"
            />
            <Metric
              label="PEAK LOAD"
              value={format(insights.peakLoadPercent)}
              suffix="%"
            />
            <Metric
              label="LINE ENVELOPE"
              value={`${format(insights.minimumLineVoltage)}–${format(insights.maximumLineVoltage)}`}
              suffix="V"
            />
            <Metric
              label="EST. ENERGY"
              value={format(insights.estimatedEnergyKwh, 3)}
              suffix="kWh"
            />
          </div>
          <Card>
            <SectionTitle
              eyebrow="Load pulse"
              title="Demand through time"
              detail="Estimated from the UPS load percentage."
            />
            <div style={{ marginTop: 18 }}>
              <Sparkline points={history} field="load" />
            </div>
          </Card>
          <div style={styles.row}>
            <Card style={{ flexGrow: 1 }}>
              <SectionTitle
                eyebrow="Battery"
                title="Charge reserve"
                detail="Directly measured percentage reported by apcupsd."
              />
              <div style={{ marginTop: 18 }}>
                <Sparkline
                  points={history}
                  field="battery"
                  color={colors.lime}
                />
              </div>
            </Card>
            <Card style={{ flexGrow: 1 }}>
              <SectionTitle
                eyebrow="Runtime"
                title="Estimated runway"
                detail="UPS-provided estimate; not a measured discharge result."
              />
              <div style={{ marginTop: 18 }}>
                <Sparkline
                  points={history}
                  field="runtime"
                  color={colors.amber}
                />
              </div>
            </Card>
          </div>
          <StatePanel
            tone="neutral"
            title={`Estimated energy cost · ${format(insights.estimatedCost, 3)}`}
            detail={`Uses the nominal watt rating, reported load percentage, and your ${energyRate.toFixed(3)}/kWh energy rate.`}
          />
        </>
      )}
    </div>
  )
}

function format(value: number | null, digits = 1): string {
  return value === null ? '—' : value.toFixed(digits)
}
