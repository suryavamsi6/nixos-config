import { describe, expect, it } from 'vitest'
import {
  editSettings,
  initialSettings,
  settingsSaved,
} from '../src/domain/settings'
describe('settings draft/effective model', () => {
  it('keeps effective values until save', () => {
    const start = initialSettings()
    const draft = editSettings(start, { minutes: 12 })
    expect(draft.effective.minutes).toBe(5)
    expect(draft.draft.minutes).toBe(12)
    expect(draft.dirty).toBe(true)
    expect(settingsSaved(draft).effective.minutes).toBe(12)
  })
})
