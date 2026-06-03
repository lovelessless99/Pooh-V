<template>
  <div class="scenarios-view">
    <div v-if="loading" class="loading-state">
      <i class="pi pi-spin pi-spinner loading-icon" />
      <p>Loading scenarios…</p>
    </div>

    <div v-else-if="scenarios.length === 0" class="empty-state">
      <i class="pi pi-inbox empty-icon" />
      <p>No scenarios available</p>
    </div>

    <div v-else class="scenarios-grid">
      <Card
        v-for="s in scenarios"
        :key="s.name"
        class="scenario-card"
      >
        <template #title>
          {{ s.name }}
        </template>

        <template #content>
          <p class="scenario-desc">{{ s.description }}</p>

          <div v-if="s.extensions.length > 0" class="tags-row">
            <Tag
              v-for="ext in s.extensions"
              :key="ext"
              :value="ext"
              severity="info"
              class="ext-tag"
            />
          </div>

          <div v-if="s.tags.length > 0" class="tags-row">
            <Tag
              v-for="tag in s.tags"
              :key="tag"
              :value="tag"
              severity="secondary"
              class="label-tag"
            />
          </div>
        </template>

        <template #footer>
          <div class="card-footer">
            <Button
              label="Run"
              icon="pi pi-play"
              :loading="running === s.name"
              @click="doRun(s.name)"
              class="run-btn"
            />

            <div v-if="runResults[s.name]" class="run-result">
              <Tag
                :value="`${runResults[s.name].coverageHits.length} hits`"
                severity="success"
              />
            </div>
          </div>
        </template>
      </Card>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import Card from 'primevue/card'
import Button from 'primevue/button'
import Tag from 'primevue/tag'
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

<style scoped>
.scenarios-view {
  width: 100%;
}

.loading-state, .empty-state {
  text-align: center;
  padding: 4rem;
  opacity: 0.5;
}

.loading-icon, .empty-icon {
  font-size: 2.5rem;
  display: block;
  margin-bottom: 0.75rem;
}

.scenarios-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: 1rem;
}

.scenario-card { width: 100%; }

.scenario-desc {
  font-size: 0.88rem;
  opacity: 0.8;
  margin: 0 0 0.75rem;
  line-height: 1.5;
}

.tags-row {
  display: flex;
  flex-wrap: wrap;
  gap: 0.35rem;
  margin-bottom: 0.5rem;
}

.ext-tag { font-size: 0.75rem; }
.label-tag { font-size: 0.75rem; }

.card-footer {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.run-btn { flex-shrink: 0; }

.run-result {
  display: flex;
  align-items: center;
}
</style>
