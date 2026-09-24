import { describe, expect, it } from 'vitest'
import { isSilentHour, shouldNotifyDesktop } from '../src/domain/notifications'
import { DEFAULT_SETTINGS } from '../src/domain/settings'

describe('notification policy', () => {
  it('handles silent periods that cross midnight', () => {
    expect(isSilentHour(23, 22, 7)).toBe(true)
    expect(isSilentHour(6, 22, 7)).toBe(true)
    expect(isSilentHour(12, 22, 7)).toBe(false)
  })

  it('never suppresses enabled critical alerts for silent hours', () => {
    expect(
      shouldNotifyDesktop(
        {
          id: '1',
          severity: 'critical',
          title: 'Low battery',
          detail: 'shutdown soon',
          at: 0,
          acknowledged: false,
        },
        DEFAULT_SETTINGS,
        new Date('2026-01-01T23:00:00'),
      ),
    ).toBe(true)
  })
})
