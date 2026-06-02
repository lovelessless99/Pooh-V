import { defineStore } from 'pinia'
import type { CoverageResponse } from '@/types'

export const useCoverageStore = defineStore('coverage', {
  state: () => ({
    hit: 0,
    total: 0,
    pct: 0,
    missing: [] as string[]
  }),
  actions: {
    update(data: CoverageResponse) {
      this.hit     = data.hit
      this.total   = data.total
      this.pct     = data.pct
      this.missing = data.missing
    }
  }
})
