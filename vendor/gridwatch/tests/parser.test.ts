import { describe, expect, it } from 'vitest'
import { parseApcAccess } from '../src/backends/apcupsd/parser'
import { validatePolicy } from '../src/domain/policy'
import { capabilityProbe, normalizeStatus } from '../src/domain/ups'

const fixture = `MODEL   : Back-UPS RS 1500G-IN\nSTATUS  : ONLINE\nLINEV   : 237.0 Volts\nLOADPCT : 20.0 Percent\nBCHARGE : 100.0 Percent\nTIMELEFT: 10.7 Minutes\nBATTV   : 27.1 Volts\nNOMPOWER: 865 Watts\nSELFTEST: NO\nSENSE: Medium\nLOTRANS: 170.0 Volts\nHITRANS: 294.0 Volts\nSERIALNO: 0B2504G08071\n`

describe('apcaccess parser', () => {
  it('normalizes the RS 1500G-IN fixture', () => {
    const t = parseApcAccess(fixture, 123)
    expect(t.model).toBe('Back-UPS RS 1500G-IN')
    expect(t.status).toBe('online')
    expect(t.runtimeMinutes).toBe(10.7)
    expect(t.loadPercent).toBe(20)
    expect(capabilityProbe(t).supported).toEqual([])
    expect(capabilityProbe(t).calibrationReason).toContain(
      'not been proven safe',
    )
  })
  it('normalizes status flags', () => {
    expect(normalizeStatus('OB LB')).toBe('low-battery')
    expect(normalizeStatus('COMMLOST')).toBe('offline')
  })
})

describe('policy', () => {
  it('clamps unsafe values', () =>
    expect(validatePolicy({ batteryLevel: 999, minutes: -2 })).toEqual({
      batteryLevel: 90,
      minutes: 1,
    }))
})
