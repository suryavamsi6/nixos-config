import { describe, expect, it } from 'vitest'
import { redactDiagnostics } from '../src/domain/diagnostics'

describe('diagnostics redaction', () => {
  it('redacts sensitive keys recursively', () => {
    expect(
      redactDiagnostics({ serial: 'secret', nested: { token: 'abc', ok: 1 } }),
    ).toEqual({
      serial: '[redacted]',
      nested: { token: '[redacted]', ok: 1 },
    })
  })
})
