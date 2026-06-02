<template>
  <div class="view">
    <h2>Scenarios</h2>
    <p v-if="loading">Loading…</p>
    <ul v-else>
      <li v-for="s in scenarios" :key="s.name" style="margin-bottom:1rem">
        <strong>{{ s.name }}</strong>
        <span v-if="s.tags.length"> [{{ s.tags.join(', ') }}]</span>
        <span v-if="s.extensions.length"> — {{ s.extensions.join(', ') }}</span>
        <p style="margin:0.2rem 0">{{ s.description }}</p>
        <button @click="doRun(s.name)" :disabled="running === s.name">
          {{ running === s.name ? 'Running…' : 'Run' }}
        </button>
        <div v-if="runResults[s.name]">
          <small>Hits: {{ runResults[s.name].coverageHits.join(', ') || 'none' }}</small>
        </div>
      </li>
    </ul>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { api } from '@/api/client'
import type { ScenarioInfo, ScenarioRunResponse } from '@/types'

const scenarios  = ref<ScenarioInfo[]>([])
const loading    = ref(true)
const running    = ref<string | null>(null)
const runResults = ref<Record<string, ScenarioRunResponse>>({})

onMounted(async () => {
  try {
    const res = await api.getScenarios()
    scenarios.value = res.data
  } finally {
    loading.value = false
  }
})

async function doRun(name: string) {
  running.value = name
  try {
    const res = await api.runScenario(name)
    runResults.value[name] = res.data
  } finally {
    running.value = null
  }
}
</script>
