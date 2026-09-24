import { useMemo, useState } from 'react'
import { colors, styles } from '../../app/theme'
import type { Alert, UpsTelemetry } from '../../domain/ups'
import { Card, SectionTitle } from '../../ui/primitives'
import { StatePanel, Tag } from '../shared'

export function EventsView({
  telemetry,
  alerts,
}: {
  telemetry: UpsTelemetry
  alerts: Alert[]
}) {
  const [query, setQuery] = useState('')
  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase()
    return needle
      ? alerts.filter((alert) =>
          `${alert.title} ${alert.detail}`.toLowerCase().includes(needle),
        )
      : alerts
  }, [alerts, query])
  const critical = alerts.filter(
    (alert) => alert.severity === 'critical' && !alert.acknowledged,
  ).length
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
          eyebrow="Signal inbox"
          title="Events & alerts"
          detail="UPS state transitions and imported apcupsd service events survive app restarts."
        />
        <Tag tone={critical ? 'red' : 'lime'}>
          {critical ? `${critical} CRITICAL` : 'ALL QUIET'}
        </Tag>
      </div>
      {telemetry.status === 'offline' && (
        <StatePanel
          tone="warning"
          title="Showing the last known event archive"
          detail="Live communication is unavailable. Persisted events remain readable through the local agent when it is running."
        />
      )}
      <Card>
        <input
          value={query}
          placeholder="Search signals"
          onChange={(event) => setQuery(event.value ?? '')}
          style={{
            width: '100%',
            background: colors.panelRaised,
            color: colors.text,
            borderRadius: 10,
            borderWidth: 1,
            borderColor: colors.line,
            padding: 11,
            fontSize: 13,
          }}
        />
      </Card>
      {filtered.length === 0 ? (
        <StatePanel
          tone="success"
          title={query ? 'No matching signals' : 'No events recorded'}
          detail={
            query
              ? 'Try a different search phrase.'
              : 'Gridwatch will place power transitions, communication failures, and maintenance results here.'
          }
        />
      ) : (
        <Card>
          {filtered.map((alert) => {
            const tone =
              alert.severity === 'critical'
                ? colors.red
                : alert.severity === 'warning'
                  ? colors.amber
                  : colors.cyan
            return (
              <div
                key={alert.id}
                style={{
                  display: 'flex',
                  flexDirection: 'row',
                  gap: 14,
                  paddingTop: 14,
                  paddingBottom: 14,
                  borderBottomWidth: 1,
                  borderColor: colors.line,
                }}
              >
                <div
                  style={{
                    width: 9,
                    height: 9,
                    borderRadius: 5,
                    background: tone,
                    marginTop: 5,
                  }}
                />
                <div
                  style={{
                    display: 'flex',
                    flexDirection: 'column',
                    gap: 5,
                    flexGrow: 1,
                  }}
                >
                  <div
                    style={{
                      display: 'flex',
                      flexDirection: 'row',
                      justifyContent: 'space-between',
                    }}
                  >
                    <text
                      style={{
                        color: colors.text,
                        fontSize: 14,
                        fontWeight: 700,
                      }}
                    >
                      {alert.title}
                    </text>
                    <text style={{ color: colors.muted, fontSize: 11 }}>
                      {new Date(alert.at).toLocaleString()}
                    </text>
                  </div>
                  <text style={{ color: colors.muted, fontSize: 12 }}>
                    {alert.detail}
                  </text>
                </div>
              </div>
            )
          })}
        </Card>
      )}
    </div>
  )
}
