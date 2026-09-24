import { describe, expect, it } from 'vitest'
import { parseApcEvents } from '../src/domain/events'
describe('apcupsd events', () => {
  it('classifies outage events', () => {
    const result = parseApcEvents(
      '2026-09-06 17:40:14 +0530  Power failure.\n2026-09-06 17:41:00 +0530  Mains returned.',
    )
    expect(result[0].severity).toBe('critical')
    expect(result[1].severity).toBe('info')
  })
})
