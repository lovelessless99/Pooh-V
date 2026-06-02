<template>
  <div class="view">
    <h2>Control</h2>

    <section>
      <h3>Generate Sequences</h3>
      <form @submit.prevent="doGenerate">
        <label>Count: <input v-model.number="form.count" type="number" min="1" max="100" /></label>
        <label>Min length: <input v-model.number="form.lengthMin" type="number" min="1" /></label>
        <label>Max length: <input v-model.number="form.lengthMax" type="number" min="1" /></label>
        <fieldset>
          <legend>Extensions</legend>
          <label v-for="ext in allExtensions" :key="ext">
            <input type="checkbox" :value="ext" v-model="form.extensions" /> {{ ext }}
          </label>
        </fieldset>
        <button type="submit" :disabled="loading">
          {{ loading ? 'Generating…' : 'Generate' }}
        </button>
      </form>
      <div v-if="result">
        <p>Generated {{ result.seqs.length }} sequences.
           Coverage: {{ result.coverage.pct.toFixed(1) }}%
           ({{ result.coverage.hit }}/{{ result.coverage.total }} bins)</p>
      </div>
      <div v-if="error" style="color:red">{{ error }}</div>
    </section>

    <section>
      <h3>Reset Coverage</h3>
      <button @click="doReset" :disabled="resetting">
        {{ resetting ? 'Resetting…' : 'Reset Coverage' }}
      </button>
      <span v-if="resetDone"> Done.</span>
    </section>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive } from 'vue'
import { api } from '@/api/client'
import type { GenerateResponse } from '@/types'

const allExtensions = ['M', 'A', 'F', 'D', 'C']

const form = reactive({
  count: 10,
  lengthMin: 5,
  lengthMax: 20,
  extensions: [] as string[]
})

const loading  = ref(false)
const error    = ref<string | null>(null)
const result   = ref<GenerateResponse | null>(null)
const resetting = ref(false)
const resetDone = ref(false)

async function doGenerate() {
  loading.value = true
  error.value   = null
  result.value  = null
  try {
    const res = await api.generate({
      extensions: ['RV64I', ...form.extensions],
      count:      form.count,
      mode:       'random',
      lengthMin:  form.lengthMin,
      lengthMax:  form.lengthMax
    })
    result.value = res.data
  } catch (e) {
    error.value = String(e)
  } finally {
    loading.value = false
  }
}

async function doReset() {
  resetting.value = true
  resetDone.value = false
  try {
    await api.resetCoverage()
    resetDone.value = true
  } finally {
    resetting.value = false
  }
}
</script>
