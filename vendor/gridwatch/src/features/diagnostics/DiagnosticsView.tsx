import { mkdir } from 'node:fs/promises'
import { join } from 'node:path'
import { useState } from 'react'
import { colors, styles } from '../../app/theme'
import { diagnosticBundle } from '../../domain/diagnostics'
import type { Alert, UpsTelemetry } from '../../domain/ups'
import { Card, SectionTitle } from '../../ui/primitives'
import { ActionButton, DataRow, StatePanel, Tag } from '../shared'

export function DiagnosticsView({
  telemetry,
  alerts,
  connectionError,
}: {
  telemetry: UpsTelemetry
  alerts: Alert[]
  connectionError: string | null
}) {
  const [exportState, setExportState] = useState<string | null>(null)
  const exportDiagnostics = async () => {
    try {
      const root = join(
        process.env.XDG_STATE_HOME ??
          join(process.env.HOME ?? '/tmp', '.local/state'),
        'gridwatch',
      )
      await mkdir(root, { recursive: true })
      const path = join(
        root,
        `diagnostics-${new Date().toISOString().replaceAll(':', '-')}.json`,
      )
      await Bun.write(
        path,
        `${JSON.stringify(
          diagnosticBundle(telemetry, alerts, {
            connected: telemetry.status !== 'offline',
            connectionError,
            protocolVersion: 1,
          }),
          null,
          2,
        )}\n`,
      )
      setExportState(`Saved redacted bundle to ${path}`)
    } catch (error) {
      setExportState(error instanceof Error ? error.message : String(error))
    }
  }
  const communicationHealthy =
    telemetry.status !== 'offline' && !telemetry.stale
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
          eyebrow="Maintenance bay"
          title="Diagnostics"
          detail="Read-only health checks and privacy-preserving support export."
        />
        <Tag tone={communicationHealthy ? 'lime' : 'red'}>
          {communicationHealthy ? 'SYSTEM NOMINAL' : 'ATTENTION'}
        </Tag>
      </div>
      {!communicationHealthy && (
        <StatePanel
          tone="critical"
          title="Communication check failed"
          detail={
            connectionError ?? 'The latest telemetry is stale or unavailable.'
          }
        />
      )}
      <div style={styles.row}>
        <Card style={{ flexGrow: 1 }}>
          <SectionTitle eyebrow="Signal chain" title="Local services" />
          <DataRow
            label="Gridwatch agent"
            value={
              telemetry.rawStatus.includes('agent')
                ? 'unavailable'
                : 'reachable'
            }
          />
          <DataRow
            label="apcupsd / NIS"
            value={
              telemetry.status === 'offline' ? 'unavailable' : 'responding'
            }
          />
          <DataRow
            label="UPS communication"
            value={communicationHealthy ? 'fresh' : 'degraded'}
          />
          <DataRow label="Protocol" value="v1" />
        </Card>
        <Card style={{ flexGrow: 1 }}>
          <SectionTitle eyebrow="Archive" title="Local evidence" />
          <DataRow
            label="Persisted events loaded"
            value={alerts.length.toString()}
          />
          <DataRow
            label="Latest sample"
            value={new Date(telemetry.timestamp).toLocaleString()}
          />
          <DataRow label="Telemetry source" value={telemetry.source} />
          <DataRow label="Serial export policy" value="redacted" />
        </Card>
      </div>
      <Card>
        <SectionTitle
          eyebrow="Support bundle"
          title="Export without exposing identity"
          detail="The bundle includes the latest state, event archive, protocol status, and connection errors. Serial numbers, tokens, passwords, and credentials are recursively redacted."
        />
        <div
          style={{
            display: 'flex',
            flexDirection: 'row',
            alignItems: 'center',
            gap: 14,
            marginTop: 16,
          }}
        >
          <ActionButton
            label="Export redacted diagnostics"
            onClick={() => void exportDiagnostics()}
          />
          {exportState && (
            <text style={{ color: colors.muted, fontSize: 12 }}>
              {exportState}
            </text>
          )}
        </div>
      </Card>
    </div>
  )
}
