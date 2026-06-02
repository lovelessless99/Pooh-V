<template>
  <div class="view">
    <h2>Bandit State</h2>
    <p>{{ store.bins.length }} bins tracked. Sorted by sampling priority (α / (α+β)).</p>
    <div style="max-width:800px">
      <Bar v-if="store.bins.length > 0" :data="chartData" :options="chartOptions" />
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { Bar } from 'vue-chartjs'
import {
  Chart as ChartJS, CategoryScale, LinearScale, BarElement, Tooltip, Legend
} from 'chart.js'
import { useBanditStore } from '@/stores/bandit'

ChartJS.register(CategoryScale, LinearScale, BarElement, Tooltip, Legend)

const store = useBanditStore()

const sorted = computed(() =>
  [...store.bins].sort((a, b) => b.priority - a.priority).slice(0, 30)
)

const chartData = computed(() => ({
  labels: sorted.value.map(b => b.name),
  datasets: [{
    label: 'Priority (α/(α+β))',
    data: sorted.value.map(b => b.priority),
    backgroundColor: '#60a5fa'
  }]
}))

const chartOptions = {
  indexAxis: 'y' as const,
  responsive: true,
  scales: { x: { min: 0, max: 1 } }
}
</script>
