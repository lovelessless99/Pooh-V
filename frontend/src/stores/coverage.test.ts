import { describe, it, expect, beforeEach } from 'vitest'
import { setActivePinia, createPinia } from 'pinia'
import { useCoverageStore } from './coverage'
import type { CoverageResponse } from '@/types'

describe('useCoverageStore', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('initializes with zeros and empty missing list', () => {
    const store = useCoverageStore()
    expect(store.hit).toBe(0)
    expect(store.total).toBe(0)
    expect(store.pct).toBe(0)
    expect(store.missing).toEqual([])
  })

  it('update() sets all fields from a CoverageResponse', () => {
    const store = useCoverageStore()
    const data: CoverageResponse = { hit: 10, total: 200, pct: 5.0, missing: ['ADD', 'SUB'] }
    store.update(data)
    expect(store.hit).toBe(10)
    expect(store.total).toBe(200)
    expect(store.pct).toBe(5.0)
    expect(store.missing).toEqual(['ADD', 'SUB'])
  })
})
