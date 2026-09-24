import type { Alert } from './ups'
export interface PowerEvent {
  id: string
  at: number
  label: string
  detail: string
  severity: Alert['severity']
}
export function parseApcEvents(text: string): PowerEvent[] {
  return text
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line, index) => {
      const match = line.match(/^(\S+\s+\S+\s+\S+)\s+(.*)$/)
      const detail = match?.[2] ?? line
      const severity: Alert['severity'] = /exhausted|shutdown|failure/i.test(
        detail,
      )
        ? 'critical'
        : /battery|transfer/i.test(detail)
          ? 'warning'
          : 'info'
      return {
        id: `${index}-${line}`,
        at: Date.parse(match?.[1] ?? '') || Date.now(),
        label: detail,
        detail: line,
        severity,
      }
    })
}
