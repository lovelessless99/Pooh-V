import { describe, it, expect, beforeEach, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import { setActivePinia, createPinia } from 'pinia'
import { defineComponent } from 'vue'
import { useCoverageStore } from '@/stores/coverage'
import { useBanditStore } from '@/stores/bandit'
import { useSSE } from './useSSE'

class MockEventSource {
  static lastInstance: MockEventSource | null = null
  listeners: Record<string, Array<(e: MessageEvent) => void>> = {}
  onerror: ((e: Event) => void) | null = null

  constructor(public url: string) {
    MockEventSource.lastInstance = this
  }

  addEventListener(type: string, handler: (e: MessageEvent) => void) {
    if (!this.listeners[type]) this.listeners[type] = []
    this.listeners[type].push(handler)
  }

  close() {}

  dispatch(type: string, data: unknown) {
    const event = new MessageEvent(type, { data: JSON.stringify(data) })
    this.listeners[type]?.forEach(h => h(event))
  }
}

vi.stubGlobal('EventSource', MockEventSource)

const TestWrapper = defineComponent({
  setup() { useSSE() },
  template: '<div />'
})

describe('useSSE', () => {
  beforeEach(() => {
    MockEventSource.lastInstance = null
  })

  it('creates EventSource pointing at /api/stream on mount', () => {
    const pinia = createPinia()
    setActivePinia(pinia)
    mount(TestWrapper, { global: { plugins: [pinia] } })
    expect(MockEventSource.lastInstance).not.toBeNull()
    expect(MockEventSource.lastInstance!.url).toBe('/api/stream')
  })

  it('registers an "update" event listener', () => {
    const pinia = createPinia()
    setActivePinia(pinia)
    mount(TestWrapper, { global: { plugins: [pinia] } })
    expect(MockEventSource.lastInstance!.listeners['update']).toBeDefined()
    expect(MockEventSource.lastInstance!.listeners['update']).toHaveLength(1)
  })

  it('dispatching update event updates coverage and bandit stores', () => {
    const pinia = createPinia()
    setActivePinia(pinia)
    mount(TestWrapper, { global: { plugins: [pinia] } })

    MockEventSource.lastInstance!.dispatch('update', {
      coverage: { hit: 7, total: 100, pct: 7.0, missing: ['ADD'] },
      bandit:   { bins: [{ name: 'SUB', alpha: 2, beta: 1, priority: 0.67 }] }
    })

    const coverage = useCoverageStore()
    const bandit   = useBanditStore()
    expect(coverage.hit).toBe(7)
    expect(bandit.bins).toHaveLength(1)
    expect(bandit.bins[0].name).toBe('SUB')
  })
})
