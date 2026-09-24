export const PROTOCOL_VERSION = 1
export const MAX_REQUEST_BYTES = 64 * 1024
export const MAX_RESPONSE_BYTES = 2 * 1024 * 1024

export type AgentKind =
  | 'ping'
  | 'status'
  | 'history'
  | 'events'
  | 'settings'
  | 'set-settings'
  | 'action'
  | 'error'
  | 'alert'

export interface AgentMessage {
  version: 1
  kind: AgentKind
  requestId?: string
  payload: Record<string, unknown>
}

const kinds = new Set<AgentKind>([
  'ping',
  'status',
  'history',
  'events',
  'settings',
  'set-settings',
  'action',
  'error',
  'alert',
])

export function message(
  kind: AgentKind,
  payload: Record<string, unknown> = {},
  requestId?: string,
): AgentMessage {
  if (requestId && new TextEncoder().encode(requestId).length > 80)
    throw new Error('Gridwatch request id exceeds 80 bytes')
  return {
    version: PROTOCOL_VERSION,
    kind,
    payload,
    ...(requestId ? { requestId } : {}),
  }
}

export function parseAgentMessage(value: unknown): AgentMessage {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    throw new Error('Agent response is not an object')
  const record = value as Record<string, unknown>
  if (record.version !== PROTOCOL_VERSION)
    throw new Error('Agent protocol version mismatch')
  if (typeof record.kind !== 'string' || !kinds.has(record.kind as AgentKind))
    throw new Error('Agent response has an unknown kind')
  if (
    !record.payload ||
    typeof record.payload !== 'object' ||
    Array.isArray(record.payload)
  )
    throw new Error('Agent response payload is not an object')
  if (record.requestId !== undefined && typeof record.requestId !== 'string')
    throw new Error('Agent response requestId is invalid')
  return record as unknown as AgentMessage
}

export function assertAgentSuccess(response: AgentMessage): AgentMessage {
  if (response.kind !== 'error') return response
  const code = String(response.payload.code ?? 'agent-error')
  const detail = String(
    response.payload.message ?? 'Gridwatch agent request failed',
  )
  throw new Error(`${code}: ${detail}`)
}
