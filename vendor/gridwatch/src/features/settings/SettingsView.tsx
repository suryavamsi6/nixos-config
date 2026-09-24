import { colors, styles } from '../../app/theme'
import type { SettingsState } from '../../domain/settings'
import type { GridwatchSettings, UpsTelemetry } from '../../domain/ups'
import { Card, SectionTitle } from '../../ui/primitives'
import { ActionButton, DataRow, NumericField, StatePanel, Tag } from '../shared'

export function SettingsView({
  telemetry,
  settings,
  onEdit,
  onSave,
  onDiscard,
}: {
  telemetry: UpsTelemetry
  settings: SettingsState | null
  onEdit: (patch: Partial<GridwatchSettings>) => void
  onSave: () => void
  onDiscard: () => void
}) {
  if (!settings)
    return (
      <div style={styles.page}>
        <SectionTitle eyebrow="Control plane" title="Settings" />
        <StatePanel
          title="Loading effective configuration"
          detail="Reading the agent-owned policy over the local socket…"
        />
      </div>
    )
  const canSave =
    settings.dirty && !settings.saving && telemetry.status !== 'offline'
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
          eyebrow="Control plane"
          title="Settings"
          detail="Drafts remain local until an authenticated save succeeds."
        />
        <Tag tone={settings.dirty ? 'amber' : 'lime'}>
          {settings.dirty ? 'UNSAVED DRAFT' : 'EFFECTIVE'}
        </Tag>
      </div>
      {telemetry.status === 'offline' && (
        <StatePanel
          tone="critical"
          title="Saving is disabled"
          detail="The privileged agent or UPS is unavailable. Your draft remains visible and the effective policy is unchanged."
        />
      )}
      {settings.error && (
        <StatePanel
          tone="critical"
          title="Policy was not changed"
          detail={settings.error}
        />
      )}
      <Card>
        <SectionTitle
          eyebrow="Shutdown policy"
          title="Protect the host before reserve is exhausted"
          detail="Gridwatch applies the first threshold reached. Values are clamped, then written atomically to the runtime apcupsd configuration with health verification and rollback."
        />
        <div style={{ ...styles.row, marginTop: 18 }}>
          <NumericField
            label="BATTERY RESERVE"
            value={settings.draft.batteryLevel}
            suffix="%"
            onChange={(batteryLevel) => onEdit({ batteryLevel })}
          />
          <NumericField
            label="TIME ON BATTERY"
            value={settings.draft.minutes}
            suffix="min"
            onChange={(minutes) => onEdit({ minutes })}
          />
        </div>
        <DataRow
          label="Effective reserve"
          value={`${settings.effective.batteryLevel}% / ${settings.effective.minutes} min`}
          note="Enforced by the agent in the runtime apcupsd configuration when the module owns the shutdown policy."
        />
        <DataRow
          label="Shutdown action"
          value={settings.draft.shutdownAction}
          note="Hibernate requires host support and is capability-gated."
        />
        <div
          style={{
            display: 'flex',
            flexDirection: 'row',
            gap: 8,
            marginTop: 10,
          }}
        >
          <ActionButton
            label="Use shutdown"
            tone={
              settings.draft.shutdownAction === 'shutdown' ? 'primary' : 'quiet'
            }
            onClick={() => onEdit({ shutdownAction: 'shutdown' })}
          />
          <ActionButton
            label="Use hibernate"
            tone={
              settings.draft.shutdownAction === 'hibernate'
                ? 'primary'
                : 'quiet'
            }
            onClick={() => onEdit({ shutdownAction: 'hibernate' })}
          />
        </div>
      </Card>
      <div style={styles.row}>
        <Card style={{ flexGrow: 1 }}>
          <SectionTitle
            eyebrow="Signals"
            title="Notifications"
            detail="Critical alerts always remain in the in-app archive."
          />
          <DataRow
            label="On-battery desktop alert"
            value={settings.draft.notifyOnBattery ? 'enabled' : 'disabled'}
          />
          <ActionButton
            label={
              settings.draft.notifyOnBattery
                ? 'Disable on-battery alert'
                : 'Enable on-battery alert'
            }
            tone="quiet"
            onClick={() =>
              onEdit({ notifyOnBattery: !settings.draft.notifyOnBattery })
            }
          />
          <DataRow
            label="Critical desktop alert"
            value={settings.draft.notifyCritical ? 'enabled' : 'disabled'}
          />
          <ActionButton
            label={
              settings.draft.notifyCritical
                ? 'Disable critical alert'
                : 'Enable critical alert'
            }
            tone="quiet"
            onClick={() =>
              onEdit({ notifyCritical: !settings.draft.notifyCritical })
            }
          />
          <div style={{ ...styles.row, marginTop: 12 }}>
            <NumericField
              label="SILENT FROM"
              value={settings.draft.silentHoursStart}
              suffix="h"
              onChange={(silentHoursStart) => onEdit({ silentHoursStart })}
            />
            <NumericField
              label="SILENT UNTIL"
              value={settings.draft.silentHoursEnd}
              suffix="h"
              onChange={(silentHoursEnd) => onEdit({ silentHoursEnd })}
            />
          </div>
        </Card>
        <Card style={{ flexGrow: 1 }}>
          <SectionTitle
            eyebrow="Archive"
            title="Retention & cost"
            detail="Hourly aggregates are retained indefinitely."
          />
          <NumericField
            label="RAW SAMPLES"
            value={settings.draft.rawRetentionHours}
            suffix="hours"
            onChange={(rawRetentionHours) => onEdit({ rawRetentionHours })}
          />
          <div style={{ height: 10 }} />
          <NumericField
            label="MINUTE ROLLUPS"
            value={settings.draft.minuteRetentionDays}
            suffix="days"
            onChange={(minuteRetentionDays) => onEdit({ minuteRetentionDays })}
          />
          <div style={{ height: 10 }} />
          <NumericField
            label="ENERGY RATE"
            value={settings.draft.energyRate}
            suffix="/kWh"
            onChange={(energyRate) => onEdit({ energyRate })}
          />
          <div style={{ height: 10 }} />
          <NumericField
            label="SELF-TEST CADENCE"
            value={settings.draft.selfTestCadenceDays}
            suffix="days"
            onChange={(selfTestCadenceDays) => onEdit({ selfTestCadenceDays })}
          />
        </Card>
      </div>
      <Card>
        <SectionTitle
          eyebrow="UPS controls"
          title="Capability-gated hardware configuration"
        />
        <text style={{ color: colors.muted, fontSize: 13, marginTop: 10 }}>
          Sensitivity {telemetry.sensitivity ?? 'not reported'} · transfer
          window {telemetry.lowTransferVoltage ?? '—'}–
          {telemetry.highTransferVoltage ?? '—'} V. These values remain
          read-only until the agent proves a safe write path for this exact
          model.
        </text>
      </Card>
      <div
        style={{
          display: 'flex',
          flexDirection: 'row',
          justifyContent: 'flex-end',
          gap: 10,
        }}
      >
        <ActionButton
          label="Discard draft"
          tone="quiet"
          disabled={!settings.dirty || settings.saving}
          onClick={onDiscard}
        />
        <ActionButton
          label={settings.saving ? 'Saving…' : 'Authenticate & save'}
          disabled={!canSave}
          onClick={onSave}
        />
      </div>
    </div>
  )
}
