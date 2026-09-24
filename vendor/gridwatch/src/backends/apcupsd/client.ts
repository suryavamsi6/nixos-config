import {
  AgentClient,
  type AgentEvent,
  type HistoryQuery,
} from '../../agent-client/client'
import type { AgentMessage } from '../../agent-client/protocol'
import { validateSettings } from '../../domain/settings'
import type {
  Alert,
  Capability,
  GridwatchSettings,
  MaintenanceStatus,
  UpsTelemetry,
} from '../../domain/ups'
import type { HistoryPoint } from '../../storage/history'
import { demoTelemetry } from './demo'
import { offlineTelemetry, parseApcAccess } from './parser'

interface AgentTransport {
  status(): Promise<AgentMessage>
  history(query?: HistoryQuery): Promise<AgentMessage>
  events(limit?: number): Promise<AgentMessage>
  settings(): Promise<AgentMessage>
  setSettings(settings: GridwatchSettings): Promise<AgentMessage>
  action(
    action: string,
    parameters?: Record<string, unknown>,
  ): Promise<AgentMessage>
}

export interface TelemetrySource {
  read(): Promise<UpsTelemetry>
  history(query?: HistoryQuery): Promise<HistoryPoint[]>
  events(limit?: number): Promise<Alert[]>
  settings(): Promise<GridwatchSettings>
  setSettings(settings: GridwatchSettings): Promise<GridwatchSettings>
  action(
    action: string,
    parameters?: Record<string, unknown>,
  ): Promise<Record<string, unknown>>
}

export class ApcAccessSource implements TelemetrySource {
  private readonly demo = process.env.GRIDWATCH_DEMO === '1'
  private demoMaintenance = demoTelemetry().maintenance

  constructor(private readonly agent: AgentTransport = new AgentClient()) {}

  async read(): Promise<UpsTelemetry> {
    if (this.demo) {
      const telemetry = demoTelemetry(Date.now(), Math.floor(Date.now() / 5000))
      return { ...telemetry, maintenance: this.demoMaintenance }
    }
    try {
      const response = await this.agent.status()
      const available = response.payload.available === true
      const sampledAt = numberValue(response.payload.sampledAt) ?? Date.now()
      const raw = stringValue(response.payload.raw)
      if (!available || !raw)
        return offlineTelemetry(
          sampledAt,
          stringValue(response.payload.error) ?? 'COMMLOST',
        )
      const parsed = parseApcAccess(raw, sampledAt)
      const capabilities = isRecord(response.payload.capabilities)
        ? response.payload.capabilities
        : {}
      const supported: Capability[] = []
      if (capabilities.selfTest === true) supported.push('self-test')
      if (capabilities.runtimeCalibration === true)
        supported.push('runtime-calibration')
      return {
        ...parsed,
        capabilities: supported,
        capabilityReason:
          stringValue(capabilities.reason) ?? parsed.capabilityReason,
        maintenance: maintenanceValue(response.payload.maintenance),
      }
    } catch (error) {
      return offlineTelemetry(
        Date.now(),
        error instanceof Error ? error.message : String(error),
      )
    }
  }

  async history(query: HistoryQuery = {}): Promise<HistoryPoint[]> {
    if (this.demo) return []
    const response = await this.agent.history(query)
    const items = arrayValue(response.payload.items)
    return items.flatMap((item) => {
      if (!isRecord(item)) return []
      if (typeof item.raw === 'string') {
        const telemetry = parseApcAccess(
          item.raw,
          numberValue(item.timestamp) ?? Date.now(),
        )
        return [historyPoint(telemetry)]
      }
      const timestamp = numberValue(item.timestamp)
      if (timestamp === null) return []
      return [
        {
          timestamp,
          load: numberValue(item.load),
          battery: numberValue(item.battery),
          runtime: numberValue(item.runtime),
          line: average(numberValue(item.lineMin), numberValue(item.lineMax)),
        },
      ]
    })
  }

  async events(limit = 100): Promise<Alert[]> {
    if (this.demo) return []
    const response = await this.agent.events(limit)
    return arrayValue(response.payload.items).flatMap((item) => {
      if (!isAgentEvent(item)) return []
      return [eventAlert(item)]
    })
  }

  async settings(): Promise<GridwatchSettings> {
    if (this.demo) return validateSettings({})
    const response = await this.agent.settings()
    return settingsValue(response.payload.effective)
  }

  async setSettings(settings: GridwatchSettings): Promise<GridwatchSettings> {
    if (this.demo) return settings
    const response = await this.agent.setSettings(settings)
    return settingsValue(response.payload.effective)
  }

  async action(
    action: string,
    parameters: Record<string, unknown> = {},
  ): Promise<Record<string, unknown>> {
    if (this.demo) {
      const now = Date.now()
      if (action === 'prepare-manual-calibration' && this.demoMaintenance)
        this.demoMaintenance = {
          ...this.demoMaintenance,
          phase: 'prepared',
          operation: 'manual-calibration',
          progress: 100,
          message: 'Demo readiness checks passed. Confirmation is required.',
          challenge: 'demo-confirmation',
          preparedAt: now,
          challengeExpiresAt: now + 600_000,
          updatedAt: now,
        }
      if (action === 'confirm-maintenance' && this.demoMaintenance)
        this.demoMaintenance = {
          ...this.demoMaintenance,
          phase: 'running',
          progress: 12,
          message: 'Demo manual discharge is being monitored.',
          challenge: undefined,
          startedAt: now,
          updatedAt: now,
        }
      if (action === 'schedule-manual-calibration' && this.demoMaintenance)
        this.demoMaintenance = {
          ...this.demoMaintenance,
          phase: 'scheduled',
          scheduledAt: numberValue(parameters.scheduledAt),
          message: 'Demo calibration window scheduled.',
          updatedAt: now,
        }
      if (action === 'abort-maintenance' && this.demoMaintenance)
        this.demoMaintenance = {
          ...this.demoMaintenance,
          phase: 'aborted',
          message: 'Demo maintenance stopped safely.',
          updatedAt: now,
        }
      return (this.demoMaintenance ?? {
        result: 'simulated',
        action,
      }) as unknown as Record<string, unknown>
    }
    return (await this.agent.action(action, parameters)).payload
  }
}

function historyPoint(telemetry: UpsTelemetry): HistoryPoint {
  return {
    timestamp: telemetry.timestamp,
    load: telemetry.loadPercent,
    battery: telemetry.batteryPercent,
    runtime: telemetry.runtimeMinutes,
    line: telemetry.lineVoltage,
  }
}

function eventAlert(event: AgentEvent): Alert {
  const title =
    event.code === 'ups.status.changed'
      ? 'UPS state changed'
      : event.code === 'apcupsd.event'
        ? 'APC service event'
        : 'Gridwatch signal'
  return {
    id: event.id,
    severity: event.severity,
    title,
    detail: event.message,
    at: event.at,
    acknowledged: event.acknowledged,
  }
}

function settingsValue(value: unknown): GridwatchSettings {
  if (!isRecord(value)) throw new Error('Agent returned invalid settings')
  return validateSettings(value as Partial<GridwatchSettings>)
}

function maintenanceValue(value: unknown): MaintenanceStatus | null {
  if (!isRecord(value) || typeof value.phase !== 'string') return null
  const phases = new Set([
    'idle',
    'scheduled',
    'preflight',
    'observing-load',
    'prepared',
    'running',
    'awaiting-mains',
    'recharging',
    'completed',
    'aborted',
    'blocked',
  ])
  if (!phases.has(value.phase)) return null
  return {
    phase: value.phase as MaintenanceStatus['phase'],
    operation: stringValue(value.operation),
    progress: numberValue(value.progress) ?? 0,
    message: stringValue(value.message) ?? 'Maintenance state unavailable.',
    scheduledAt: numberValue(value.scheduledAt),
    stableSince: numberValue(value.stableSince),
    preparedAt: numberValue(value.preparedAt),
    challengeExpiresAt: numberValue(value.challengeExpiresAt),
    startedAt: numberValue(value.startedAt),
    updatedAt: numberValue(value.updatedAt) ?? Date.now(),
    cooldownUntil: numberValue(value.cooldownUntil),
    baselineRuntimeMinutes: numberValue(value.baselineRuntimeMinutes),
    resultRuntimeMinutes: numberValue(value.resultRuntimeMinutes),
    seenOnBattery: value.seenOnBattery === true,
    ...(typeof value.challenge === 'string'
      ? { challenge: value.challenge }
      : {}),
  }
}

function isAgentEvent(value: unknown): value is AgentEvent {
  if (!isRecord(value)) return false
  return (
    typeof value.id === 'string' &&
    typeof value.at === 'number' &&
    typeof value.code === 'string' &&
    typeof value.message === 'string' &&
    typeof value.source === 'string' &&
    typeof value.acknowledged === 'boolean' &&
    (value.severity === 'info' ||
      value.severity === 'warning' ||
      value.severity === 'critical')
  )
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value)
}

function arrayValue(value: unknown): unknown[] {
  return Array.isArray(value) ? value : []
}

function stringValue(value: unknown): string | null {
  return typeof value === 'string' ? value : null
}

function numberValue(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

function average(first: number | null, second: number | null): number | null {
  if (first === null) return second
  if (second === null) return first
  return (first + second) / 2
}
