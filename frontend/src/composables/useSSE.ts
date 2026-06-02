import { onMounted, onUnmounted } from 'vue'
import { useCoverageStore } from '@/stores/coverage'
import { useBanditStore } from '@/stores/bandit'
import type { SSEEvent } from '@/types'

export function useSSE() {
  let es: EventSource | null = null
  const coverage = useCoverageStore()
  const bandit   = useBanditStore()

  function connect() {
    es = new EventSource('/api/stream')
    es.addEventListener('update', (e: MessageEvent) => {
      const data = JSON.parse(e.data) as SSEEvent
      coverage.update(data.coverage)
      bandit.update(data.bandit)
    })
    es.onerror = () => {
      es?.close()
      setTimeout(connect, 3000)
    }
  }

  onMounted(connect)
  onUnmounted(() => es?.close())
}
