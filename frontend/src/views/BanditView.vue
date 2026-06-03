<template>
  <div class="bandit-view">
    <Card>
      <template #title>Bandit State</template>
      <template #subtitle>
        {{ store.bins.length }} bins tracked — sorted by sampling priority (α / (α+β))
      </template>
      <template #content>
        <div v-if="sorted.length === 0" class="empty-state">
          <i class="pi pi-inbox empty-icon" />
          <p>No bandit data yet</p>
        </div>

        <DataTable
          v-else
          :value="sorted"
          :rows="50"
          stripedRows
          class="bandit-table"
          size="small"
        >
          <Column header="#" style="width: 3rem; text-align: center;">
            <template #body="{ index }">
              <span class="rank-badge">{{ index + 1 }}</span>
            </template>
          </Column>

          <Column field="name" header="Bin Name" sortable>
            <template #body="{ data }">
              <span class="bin-name">{{ data.name }}</span>
            </template>
          </Column>

          <Column field="alpha" header="α" sortable style="width: 5rem;">
            <template #body="{ data }">
              {{ data.alpha.toFixed(2) }}
            </template>
          </Column>

          <Column field="beta" header="β" sortable style="width: 5rem;">
            <template #body="{ data }">
              {{ data.beta.toFixed(2) }}
            </template>
          </Column>

          <Column field="priority" header="Priority" sortable style="width: 12rem;">
            <template #body="{ data }">
              <div class="priority-cell">
                <ProgressBar
                  :value="data.priority * 100"
                  :showValue="false"
                  class="priority-bar"
                />
                <span class="priority-label">{{ (data.priority * 100).toFixed(1) }}%</span>
              </div>
            </template>
          </Column>

          <Column field="priority" header="Score" style="width: 6rem;">
            <template #body="{ data }">
              <Tag
                :value="data.priority.toFixed(3)"
                :severity="scoreSeverity(data.priority)"
              />
            </template>
          </Column>
        </DataTable>
      </template>
    </Card>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import Card from 'primevue/card'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import ProgressBar from 'primevue/progressbar'
import Tag from 'primevue/tag'
import { useBanditStore } from '@/stores/bandit'

const store = useBanditStore()

const sorted = computed(() =>
  [...store.bins].sort((a, b) => b.priority - a.priority).slice(0, 50)
)

function scoreSeverity(priority: number): 'success' | 'warn' | 'danger' | 'info' {
  if (priority >= 0.7) return 'success'
  if (priority >= 0.4) return 'warn'
  return 'danger'
}
</script>

<style scoped>
.bandit-view {
  max-width: 1000px;
}

.empty-state {
  text-align: center;
  padding: 3rem;
  opacity: 0.5;
}

.empty-icon {
  font-size: 2.5rem;
  display: block;
  margin-bottom: 0.5rem;
}

.rank-badge {
  display: inline-block;
  width: 1.8rem;
  height: 1.8rem;
  line-height: 1.8rem;
  text-align: center;
  border-radius: 50%;
  background: var(--p-primary-100, #e0e7ff);
  color: var(--p-primary-700, #4338ca);
  font-size: 0.78rem;
  font-weight: 600;
}

.bin-name {
  font-family: monospace;
  font-size: 0.85rem;
}

.priority-cell {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.priority-bar {
  flex: 1;
  height: 6px;
}

.priority-label {
  font-size: 0.78rem;
  min-width: 3rem;
  text-align: right;
  opacity: 0.7;
}
</style>
