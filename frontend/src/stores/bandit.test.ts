import { describe, it, expect, beforeEach } from 'vitest'
import { setActivePinia, createPinia } from 'pinia'
import { useBanditStore } from './bandit'
import type { BanditResponse } from '@/types'

describe('useBanditStore', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('initializes with empty bins array', () => {
    const store = useBanditStore()
    expect(store.bins).toEqual([])
  })

  it('update() replaces the entire bins array', () => {
    const store = useBanditStore()
    const data: BanditResponse = {
      bins: [{ name: 'ADD', alpha: 1.5, beta: 2.0, priority: 0.43 }]
    }
    store.update(data)
    expect(store.bins).toHaveLength(1)
    expect(store.bins[0].name).toBe('ADD')
    expect(store.bins[0].priority).toBeCloseTo(0.43)
  })

  it('update() called twice keeps only the latest data', () => {
    const store = useBanditStore()
    store.update({ bins: [{ name: 'ADD', alpha: 1, beta: 1, priority: 0.5 }] })
    store.update({ bins: [] })
    expect(store.bins).toHaveLength(0)
  })
})
