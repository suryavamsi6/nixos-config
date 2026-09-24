const SECRET_KEYS = /serial|password|token|secret|credential/i
export function redactDiagnostics(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(redactDiagnostics)
  if (value && typeof value === 'object')
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [
        key,
        SECRET_KEYS.test(key) ? '[redacted]' : redactDiagnostics(item),
      ]),
    )
  return value
}
export function diagnosticBundle(
  status: unknown,
  events: unknown,
  agent: unknown,
) {
  return {
    generatedAt: new Date().toISOString(),
    status: redactDiagnostics(status),
    events: redactDiagnostics(events),
    agent: redactDiagnostics(agent),
    note: 'Gridwatch diagnostic bundle; secrets and serial identifiers are redacted where possible.',
  }
}
