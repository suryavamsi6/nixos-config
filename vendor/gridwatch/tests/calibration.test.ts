import { describe, expect, it } from 'vitest'
import { preflightCalibration } from '../src/domain/calibration'
import { demoTelemetry } from '../src/backends/apcupsd/demo'

describe('calibration safety gates', () => {
  it('blocks light loads', () =>
    expect(preflightCalibration(demoTelemetry()).phase).toBe('blocked'))
  it('blocks non-online state', () =>
    expect(
      preflightCalibration({ ...demoTelemetry(), status: 'on-battery' }).phase,
    ).toBe('blocked'))
  it('accepts only the bounded 30–40% load envelope', () => {
    expect(
      preflightCalibration({ ...demoTelemetry(), loadPercent: 35 }).phase,
    ).toBe('preflight')
    expect(
      preflightCalibration({ ...demoTelemetry(), loadPercent: 41 }).phase,
    ).toBe('blocked')
  })
  it('blocks stale telemetry', () =>
    expect(
      preflightCalibration({
        ...demoTelemetry(),
        loadPercent: 35,
        stale: true,
      }).phase,
    ).toBe('blocked'))
})
