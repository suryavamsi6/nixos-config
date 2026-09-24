import type { Alert } from './domain/ups'
export async function notifyDesktop(alert: Alert): Promise<void> {
  if (process.env.GRIDWATCH_DEMO === '1') return
  try {
    Bun.spawn([
      'notify-send',
      '--urgency',
      alert.severity === 'critical' ? 'critical' : 'normal',
      'Gridwatch',
      `${alert.title}\n${alert.detail}`,
    ])
  } catch {
    /* notification is best effort */
  }
}
