import { motion } from '@gpuix/react'
import { useEffect, useRef, useState, type ReactNode } from 'react'
import { ApcAccessSource } from '../backends/apcupsd/client'
import { shouldNotifyDesktop } from '../domain/notifications'
import {
  DEFAULT_SETTINGS,
  editSettings,
  initialSettings,
  settingsFailed,
  settingsSaved,
  type SettingsState,
} from '../domain/settings'
import {
  makeAlert,
  type Alert,
  type GridwatchSettings,
  type UpsTelemetry,
} from '../domain/ups'
import { CalibrationView } from '../features/calibration/CalibrationView'
import { DeviceView } from '../features/device/DeviceView'
import { DiagnosticsView } from '../features/diagnostics/DiagnosticsView'
import { EventsView } from '../features/events/EventsView'
import { HistoryView } from '../features/history/HistoryView'
import { SettingsView } from '../features/settings/SettingsView'
import { Overview } from '../features/views'
import { notifyDesktop } from '../notifier'
import { point, type HistoryPoint } from '../storage/history'
import { colors } from './theme'

const source = new ApcAccessSource()
const demoMode = process.env.GRIDWATCH_DEMO === '1'
const tabs = [
  'Overview',
  'History',
  'Events',
  'Device',
  'Settings',
  'Diagnostics',
  'Calibration Lab',
] as const
type Tab = (typeof tabs)[number]

export function App() {
  const [tab, setTab] = useState<Tab>('Overview')
  const [telemetry, setTelemetry] = useState<UpsTelemetry | null>(null)
  const [history, setHistory] = useState<HistoryPoint[]>([])
  const [alerts, setAlerts] = useState<Alert[]>([])
  const [settings, setSettings] = useState<SettingsState | null>(null)
  const [error, setError] = useState<string | null>(null)
  const settingsRef = useRef<GridwatchSettings>(DEFAULT_SETTINGS)

  useEffect(() => {
    let alive = true
    let previous: UpsTelemetry | undefined

    const poll = async () => {
      const next = await source.read()
      if (!alive) return
      setTelemetry(next)
      if (demoMode)
        setHistory((current) => [...current.slice(-287), point(next)])
      const localAlert = makeAlert(next, previous)
      if (
        demoMode &&
        localAlert &&
        shouldNotifyDesktop(localAlert, settingsRef.current)
      ) {
        setAlerts((current) => [localAlert, ...current].slice(0, 50))
        void notifyDesktop(localAlert)
      }
      previous = next
      setError(
        next.status === 'offline'
          ? `Gridwatch agent or UPS communication is unavailable: ${next.rawStatus}`
          : null,
      )
    }

    const refreshPersistentData = async () => {
      if (demoMode) return
      try {
        const [savedHistory, savedAlerts] = await Promise.all([
          source.history({
            from: Date.now() - 24 * 60 * 60 * 1000,
            resolution: 'minute',
            limit: 1440,
          }),
          source.events(100),
        ])
        if (!alive) return
        setHistory(savedHistory)
        setAlerts(savedAlerts)
      } catch (problem) {
        if (alive)
          setError(
            problem instanceof Error
              ? problem.message
              : 'Could not query the Gridwatch agent.',
          )
      }
    }

    const loadSettings = async () => {
      try {
        const effective = await source.settings()
        settingsRef.current = effective
        if (alive) setSettings(initialSettings(effective))
      } catch (problem) {
        if (alive) {
          setSettings(initialSettings())
          setError(problem instanceof Error ? problem.message : String(problem))
        }
      }
    }

    void poll()
    void refreshPersistentData()
    void loadSettings()
    const pollTimer = setInterval(() => void poll(), 5000)
    const dataTimer = setInterval(() => void refreshPersistentData(), 15_000)
    return () => {
      alive = false
      clearInterval(pollTimer)
      clearInterval(dataTimer)
    }
  }, [])

  const edit = (patch: Partial<GridwatchSettings>) =>
    setSettings((current) => (current ? editSettings(current, patch) : current))
  const discard = () =>
    setSettings((current) =>
      current ? initialSettings(current.effective) : current,
    )
  const save = async () => {
    if (!settings || settings.saving || !settings.dirty) return
    const draft = settings.draft
    setSettings((current) =>
      current ? { ...current, saving: true, error: null } : current,
    )
    try {
      const effective = await source.setSettings(draft)
      settingsRef.current = effective
      setSettings((current) =>
        current ? settingsSaved(current, effective) : current,
      )
    } catch (problem) {
      setSettings((current) =>
        current
          ? settingsFailed(
              current,
              problem instanceof Error ? problem.message : String(problem),
            )
          : current,
      )
    }
  }
  const runMaintenanceAction = async (
    action: string,
    parameters: Record<string, unknown> = {},
  ) => {
    setError(null)
    try {
      await source.action(action, parameters)
      setTelemetry(await source.read())
    } catch (problem) {
      const message =
        problem instanceof Error ? problem.message : String(problem)
      setError(message)
      throw problem
    }
  }

  let content: ReactNode
  if (!telemetry) {
    content = (
      <div style={{ color: colors.muted, fontSize: 15, padding: 28 }}>
        Connecting to the Gridwatch agent…
      </div>
    )
  } else {
    switch (tab) {
      case 'Overview':
        content = (
          <Overview telemetry={telemetry} history={history} alerts={alerts} />
        )
        break
      case 'History':
        content = (
          <HistoryView
            telemetry={telemetry}
            history={history}
            energyRate={settings?.effective.energyRate}
          />
        )
        break
      case 'Events':
        content = <EventsView telemetry={telemetry} alerts={alerts} />
        break
      case 'Device':
        content = <DeviceView telemetry={telemetry} />
        break
      case 'Settings':
        content = (
          <SettingsView
            telemetry={telemetry}
            settings={settings}
            onEdit={edit}
            onSave={() => void save()}
            onDiscard={discard}
          />
        )
        break
      case 'Diagnostics':
        content = (
          <DiagnosticsView
            telemetry={telemetry}
            alerts={alerts}
            connectionError={error}
          />
        )
        break
      case 'Calibration Lab':
        content = (
          <CalibrationView
            telemetry={telemetry}
            onAction={runMaintenanceAction}
          />
        )
        break
    }
  }

  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'row',
        minHeight: 900,
        background: colors.bg,
      }}
    >
      <div
        style={{
          width: 215,
          background: {
            type: 'linear-gradient',
            angle: 180,
            stops: [
              { color: '#091a1f', position: 0 },
              { color: '#071216', position: 1 },
            ],
          },
          borderRightWidth: 1,
          borderColor: '#173238',
          padding: 20,
          display: 'flex',
          flexDirection: 'column',
          gap: 8,
        }}
      >
        <text
          style={{
            color: colors.text,
            fontSize: 22,
            fontWeight: 800,
            marginBottom: 3,
          }}
        >
          GRID<text style={{ color: colors.cyan }}>WATCH</text>
        </text>
        <text style={{ color: colors.muted, fontSize: 10, marginBottom: 18 }}>
          ELECTRIC OBSERVATORY
        </text>
        {tabs.map((item, index) => (
          <div
            key={item}
            onClick={() => setTab(item)}
            aria-label={item}
            style={{
              padding: 12,
              borderRadius: 10,
              background: tab === item ? '#143138' : 'transparent',
              color: tab === item ? colors.text : colors.muted,
              fontSize: 13,
              fontWeight: tab === item ? 700 : 400,
              cursor: 'pointer',
              hover: { background: '#112b31' },
            }}
          >
            {`${String(index + 1).padStart(2, '0')}  ${item}`}
          </div>
        ))}
        <div style={{ flexGrow: 1 }} />
        <div
          style={{
            padding: 11,
            borderRadius: 10,
            background: '#0d2227',
            display: 'flex',
            flexDirection: 'column',
            gap: 4,
          }}
        >
          <text style={{ color: colors.text, fontSize: 11 }}>
            {telemetry?.model ?? 'APC UPS'}
          </text>
          <text
            style={{
              color: demoMode ? colors.amber : colors.cyan,
              fontSize: 10,
            }}
          >
            {demoMode ? 'SIMULATION MODE' : 'LOCAL AGENT'}
          </text>
        </div>
      </div>
      <div style={{ flexGrow: 1, overflow: 'scroll' }}>
        {error && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            style={{
              padding: 12,
              background: '#3a2027',
              color: '#ffc4c8',
              fontSize: 13,
            }}
          >
            {error}
          </motion.div>
        )}
        {content}
      </div>
    </div>
  )
}
