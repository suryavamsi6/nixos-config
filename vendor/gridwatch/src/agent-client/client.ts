import { createConnection, type Socket } from 'node:net'
import type { GridwatchSettings } from '../domain/ups'
import {
  assertAgentSuccess,
  MAX_REQUEST_BYTES,
  MAX_RESPONSE_BYTES,
  message,
  parseAgentMessage,
  type AgentKind,
  type AgentMessage,
} from './protocol'

const DEFAULT_TIMEOUT_MS = 10_000
const MUTATION_TIMEOUT_MS = 120_000

export interface HistoryQuery {
  from?: number
  to?: number
  resolution?: 'raw' | 'minute' | 'hour'
  limit?: number
}

export interface AgentEvent {
  id: string
  at: number
  code: string
  severity: 'info' | 'warning' | 'critical'
  message: string
  source: string
  acknowledged: boolean
}

export class AgentClient {
  constructor(
    private readonly socketPath = process.env.GRIDWATCH_SOCKET ??
      '/run/gridwatch/agent.sock',
    private readonly timeoutMs = DEFAULT_TIMEOUT_MS,
  ) {}

  request(
    kind: AgentKind,
    payload: Record<string, unknown> = {},
  ): Promise<AgentMessage> {
    const requestId = crypto.randomUUID()
    const outbound = `${JSON.stringify(message(kind, payload, requestId))}\n`
    if (Buffer.byteLength(outbound) > MAX_REQUEST_BYTES)
      return Promise.reject(new Error('Gridwatch agent request is too large'))

    return new Promise((resolve, reject) => {
      let settled = false
      let received = ''
      let socket: Socket
      const finish = (error?: Error, response?: AgentMessage) => {
        if (settled) return
        settled = true
        clearTimeout(timer)
        socket?.destroy()
        if (error) reject(error)
        else resolve(response as AgentMessage)
      }
      const requestTimeout =
        kind === 'action' || kind === 'set-settings'
          ? Math.max(this.timeoutMs, MUTATION_TIMEOUT_MS)
          : this.timeoutMs
      const timer = setTimeout(
        () => finish(new Error('Gridwatch agent request timed out')),
        requestTimeout,
      )

      socket = createConnection({ path: this.socketPath })
      socket.setEncoding('utf8')
      socket.once('connect', () => socket.write(outbound))
      socket.on('data', (chunk: string) => {
        received += chunk
        if (Buffer.byteLength(received) > MAX_RESPONSE_BYTES) {
          finish(
            new Error('Gridwatch agent response exceeded the safety limit'),
          )
          return
        }
        const newline = received.indexOf('\n')
        if (newline < 0) return
        try {
          const response = assertAgentSuccess(
            parseAgentMessage(JSON.parse(received.slice(0, newline))),
          )
          if (response.requestId !== requestId)
            throw new Error('Gridwatch agent response id mismatch')
          finish(undefined, response)
        } catch (error) {
          finish(error instanceof Error ? error : new Error(String(error)))
        }
      })
      socket.once('error', (error) => finish(error))
      socket.once('end', () => {
        if (!settled)
          finish(
            new Error(
              'Gridwatch agent closed the connection without a response',
            ),
          )
      })
    })
  }

  ping() {
    return this.request('ping')
  }

  status() {
    return this.request('status')
  }

  history(query: HistoryQuery = {}) {
    return this.request('history', { ...query })
  }

  events(limit = 100) {
    return this.request('events', { limit })
  }

  settings() {
    return this.request('settings')
  }

  setSettings(settings: GridwatchSettings) {
    return this.request('set-settings', { ...settings })
  }

  action(action: string, parameters: Record<string, unknown> = {}) {
    return this.request('action', { action, ...parameters })
  }
}
