import { describe, expect, it } from 'vitest'
import { ApcAccessSource } from '../src/backends/apcupsd/client'

const raw = `MODEL: Back-UPS RS 1500G-IN\nSTATUS: ONLINE\nBCHARGE: 100 Percent\nLOADPCT: 35 Percent\nTIMELEFT: 12 Minutes\n`

function response(payload: Record<string, unknown>) {
  return {
    version: 1 as const,
    kind: 'status' as const,
    requestId: 'test-request',
    payload,
  }
}

describe('ApcAccessSource status enrichment', () => {
  it('uses the agent capability report and persisted maintenance state', async () => {
    const agent = {
      status: async () =>
        response({
          available: true,
          sampledAt: 123,
          raw,
          capabilities: {
            selfTest: false,
            runtimeCalibration: false,
            manualCalibration: true,
            reason: 'Manual workflow only.',
          },
          maintenance: {
            phase: 'prepared',
            operation: 'manual-calibration',
            progress: 100,
            message: 'Confirmation required.',
            scheduledAt: null,
            stableSince: 100,
            preparedAt: 110,
            challengeExpiresAt: 710,
            startedAt: null,
            updatedAt: 120,
            cooldownUntil: null,
            baselineRuntimeMinutes: 12,
            resultRuntimeMinutes: null,
            seenOnBattery: false,
            challenge: 'challenge-token',
          },
        }),
    }

    const telemetry = await new ApcAccessSource(agent as never).read()

    expect(telemetry.capabilities).toEqual([])
    expect(telemetry.capabilityReason).toBe('Manual workflow only.')
    expect(telemetry.maintenance?.phase).toBe('prepared')
    expect(telemetry.maintenance?.challenge).toBe('challenge-token')
  })
})
