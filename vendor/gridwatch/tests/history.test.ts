import { describe, expect, it } from 'vitest'
import { downsample, type HistoryPoint } from '../src/storage/history'
describe('history', () => {
  it('keeps endpoints when downsampling', () => {
    const p: HistoryPoint[] = Array.from({ length: 100 }, (_, timestamp) => ({
      timestamp,
      load: timestamp,
      battery: 100,
      runtime: 10,
      line: 230,
    }))
    const out = downsample(p, 10)
    expect(out).toHaveLength(10)
    expect(out[0].timestamp).toBe(0)
    expect(out.at(-1)?.timestamp).toBe(99)
  })
})
