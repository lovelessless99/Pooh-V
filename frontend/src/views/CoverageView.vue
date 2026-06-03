<template>
  <div class="coverage-view">
    <!-- Stat Cards Row -->
    <div class="stats-row">
      <Card class="stat-card">
        <template #header>
          <div class="stat-card-header">
            <i class="pi pi-check-circle stat-icon stat-icon--success" />
          </div>
        </template>
        <template #title>Bins Hit</template>
        <template #content>
          <div class="stat-value">{{ store.hit }} <span class="stat-denom">/ {{ store.total }}</span></div>
        </template>
      </Card>

      <Card class="stat-card">
        <template #header>
          <div class="stat-card-header">
            <i class="pi pi-chart-pie stat-icon stat-icon--primary" />
          </div>
        </template>
        <template #title>Coverage</template>
        <template #content>
          <div class="stat-value">{{ store.pct.toFixed(1) }}<span class="stat-unit">%</span></div>
          <ProgressBar :value="store.pct" :showValue="false" class="coverage-bar" />
        </template>
      </Card>

      <Card class="stat-card">
        <template #header>
          <div class="stat-card-header">
            <i class="pi pi-exclamation-triangle stat-icon stat-icon--warn" />
          </div>
        </template>
        <template #title>Missing</template>
        <template #content>
          <div class="stat-value">{{ store.total - store.hit }} <span class="stat-unit">bins</span></div>
        </template>
      </Card>
    </div>

    <!-- Main Content Row -->
    <div class="content-row">
      <!-- Chart -->
      <Card class="chart-card">
        <template #title>Coverage Breakdown</template>
        <template #content>
          <div v-if="store.total > 0" class="chart-wrapper">
            <Doughnut :data="chartData" :options="chartOptions" />
          </div>
          <div v-else class="empty-state">
            <i class="pi pi-inbox empty-icon" />
            <p>No coverage data yet</p>
          </div>
        </template>
      </Card>

      <!-- Missing Bins -->
      <Card class="missing-card">
        <template #title>Missing Bins</template>
        <template #content>
          <div v-if="store.missing.length === 0 && store.total > 0" class="all-covered">
            <i class="pi pi-check-circle" style="color: #22c55e; font-size: 2rem;" />
            <p>All bins covered!</p>
          </div>
          <div v-else-if="store.missing.length > 0" class="missing-list">
            <div class="missing-count">
              Showing {{ Math.min(store.missing.length, 50) }} of {{ store.missing.length }}
            </div>
            <div class="tags-grid">
              <Tag
                v-for="bin in store.missing.slice(0, 50)"
                :key="bin"
                :value="bin"
                severity="danger"
                class="bin-tag"
              />
            </div>
          </div>
          <div v-else class="empty-state">
            <i class="pi pi-inbox empty-icon" />
            <p>No data</p>
          </div>
        </template>
      </Card>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { Doughnut } from 'vue-chartjs'
import { Chart as ChartJS, ArcElement, Tooltip, Legend } from 'chart.js'
import Card from 'primevue/card'
import ProgressBar from 'primevue/progressbar'
import Tag from 'primevue/tag'
import { useCoverageStore } from '@/stores/coverage'

ChartJS.register(ArcElement, Tooltip, Legend)

const store = useCoverageStore()

const chartData = computed(() => ({
  labels: ['Hit', 'Missing'],
  datasets: [{
    data: [store.hit, store.total - store.hit],
    backgroundColor: ['#6366f1', '#334155'],
    borderColor: ['#6366f1', '#334155'],
    borderWidth: 1
  }]
}))

const chartOptions = {
  responsive: true,
  maintainAspectRatio: true,
  plugins: {
    legend: { position: 'bottom' as const }
  }
}
</script>

<style scoped>
.coverage-view {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.stats-row {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 1rem;
}

.stat-card-header {
  padding: 1rem 1rem 0;
}

.stat-icon {
  font-size: 1.6rem;
}
.stat-icon--success { color: #22c55e; }
.stat-icon--primary { color: #6366f1; }
.stat-icon--warn    { color: #f59e0b; }

.stat-value {
  font-size: 2rem;
  font-weight: 700;
  line-height: 1;
  margin-bottom: 0.5rem;
}
.stat-denom, .stat-unit {
  font-size: 1rem;
  font-weight: 400;
  opacity: 0.6;
}

.coverage-bar {
  height: 6px;
  margin-top: 0.5rem;
}

.content-row {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1rem;
}

.chart-wrapper {
  max-width: 300px;
  margin: 0 auto;
}

.missing-count {
  font-size: 0.8rem;
  opacity: 0.6;
  margin-bottom: 0.75rem;
}

.tags-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem;
}

.bin-tag {
  font-size: 0.75rem;
}

.empty-state {
  text-align: center;
  padding: 2rem;
  opacity: 0.5;
}

.empty-icon {
  font-size: 2.5rem;
  display: block;
  margin-bottom: 0.5rem;
}

.all-covered {
  text-align: center;
  padding: 2rem;
  color: #22c55e;
}
</style>
