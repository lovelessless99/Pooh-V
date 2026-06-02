import { defineStore } from 'pinia'
import type { BanditResponse, BinInfo } from '@/types'

export const useBanditStore = defineStore('bandit', {
  state: () => ({
    bins: [] as BinInfo[]
  }),
  actions: {
    update(data: BanditResponse) {
      this.bins = data.bins
    }
  }
})
