import { describe, expect, it } from 'vitest'
import {
  assertAgentSuccess,
  message,
  parseAgentMessage,
} from '../src/agent-client/protocol'

describe('agent protocol', () => {
  it('round-trips versioned camel-case messages', () => {
    const request = message('ping', {}, 'request-1')
    expect(parseAgentMessage(JSON.parse(JSON.stringify(request)))).toEqual(
      request,
    )
  })

  it('rejects incompatible versions and response errors', () => {
    expect(() =>
      parseAgentMessage({ version: 2, kind: 'status', payload: {} }),
    ).toThrow('version mismatch')
    expect(() =>
      assertAgentSuccess(
        parseAgentMessage({
          version: 1,
          kind: 'error',
          payload: { code: 'denied', message: 'No access' },
        }),
      ),
    ).toThrow('denied: No access')
  })

  it('bounds request identifiers', () => {
    expect(() => message('ping', {}, 'x'.repeat(81))).toThrow(
      'exceeds 80 bytes',
    )
  })
})
