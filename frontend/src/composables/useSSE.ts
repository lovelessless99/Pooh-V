import { onMounted, onUnmounted } from 'vue'
import { useCoverageStore } from '@/stores/coverage'
import { useBanditStore } from '@/stores/bandit'
import type { SSEEvent } from '@/types'

export function useSSE() {
  let es: EventSource | null = null
  const coverage = useCoverageStore()
  const bandit   = useBanditStore()

  onMounted(() => {
    es = new EventSource('/api/stream')
    es.addEventListener('update', (e: MessageEvent) => {
      const data = JSON.parse(e.data) as SSEEvent
      coverage.update(data.coverage)
      bandit.update(data.bandit)
    })
    es.onerror = () => {
      es?.close()
      setTimeout(() => {
        es = new EventSource('/api/stream')
      }, 3000)
    }
  })

  onUnmounted(() => es?.close())
}
