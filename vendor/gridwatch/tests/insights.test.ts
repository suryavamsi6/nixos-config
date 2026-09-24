import { describe, expect, it } from 'vitest'
import { historyInsights } from '../src/domain/insights'

describe('power insights', () => {
  it('integrates estimated energy from nominal watts and load', () => {
    const result = historyInsights(
      [
        { timestamp: 0, load: 50, battery: 100, runtime: 20, line: 230 },
        { timestamp: 3_600_000, load: 50, battery: 99, runtime: 19, line: 240 },
      ],
      1000,
      0.2,
    )
    expect(result.estimatedEnergyKwh).toBe(0.5)
    expect(result.estimatedCost).toBe(0.1)
    expect(result.minimumLineVoltage).toBe(230)
    expect(result.maximumLineVoltage).toBe(240)
  })
})
