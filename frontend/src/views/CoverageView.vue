<template>
  <div class="view">
    <h2>Coverage</h2>
    <div class="stats">
      <span>{{ store.hit }} / {{ store.total }} bins hit</span>
      <span> — {{ store.pct.toFixed(1) }}%</span>
    </div>
    <div class="chart-container" style="max-width:300px">
      <Doughnut v-if="store.total > 0" :data="chartData" :options="chartOptions" />
    </div>
    <div v-if="store.missing.length > 0">
      <h3>Missing bins (first 20)</h3>
      <ul>
        <li v-for="bin in store.missing" :key="bin">{{ bin }}</li>
      </ul>
    </div>
    <div v-else-if="store.total > 0">
      <p>All bins covered!</p>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { Doughnut } from 'vue-chartjs'
import { Chart as ChartJS, ArcElement, Tooltip, Legend } from 'chart.js'
import { useCoverageStore } from '@/stores/coverage'

ChartJS.register(ArcElement, Tooltip, Legend)

const store = useCoverageStore()

const chartData = computed(() => ({
  labels: ['Hit', 'Missing'],
  datasets: [{
    data: [store.hit, store.total - store.hit],
    backgroundColor: ['#4ade80', '#f87171']
  }]
}))

const chartOptions = { responsive: true }
</script>
