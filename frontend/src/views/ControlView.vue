<template>
  <div class="control-view">
    <!-- Generate Card -->
    <Card class="control-card">
      <template #title>
        <div class="card-title-row">
          <i class="pi pi-play-circle card-title-icon" />
          Generate Sequences
        </div>
      </template>
      <template #content>
        <div class="form-grid">
          <div class="form-field">
            <label class="field-label">Count</label>
            <InputNumber
              v-model="form.count"
              :min="1"
              :max="100"
              showButtons
              buttonLayout="horizontal"
              :step="1"
              class="field-input"
            />
          </div>

          <div class="form-field">
            <label class="field-label">Min Length</label>
            <InputNumber
              v-model="form.lengthMin"
              :min="1"
              showButtons
              buttonLayout="horizontal"
              :step="1"
              class="field-input"
            />
          </div>

          <div class="form-field">
            <label class="field-label">Max Length</label>
            <InputNumber
              v-model="form.lengthMax"
              :min="1"
              showButtons
              buttonLayout="horizontal"
              :step="1"
              class="field-input"
            />
          </div>
        </div>

        <div class="extensions-section">
          <label class="field-label">Extensions</label>
          <div class="extensions-row">
            <Tag value="RV64I" severity="secondary" class="ext-fixed" title="Always included" />
            <ToggleButton
              v-for="ext in allExtensions"
              :key="ext"
              v-model="extEnabled[ext]"
              :onLabel="ext"
              :offLabel="ext"
              onIcon="pi pi-check"
              offIcon="pi pi-times"
              class="ext-toggle"
            />
          </div>
        </div>

        <Button
          label="Generate"
          icon="pi pi-play"
          :loading="loading"
          size="large"
          class="generate-btn"
          @click="doGenerate"
        />

        <!-- Result message -->
        <Message v-if="result" severity="success" class="result-msg" :closable="false">
          <div class="result-content">
            <i class="pi pi-check-circle" />
            Generated <strong>{{ result.seqs.length }}</strong> sequences —
            Coverage: <strong>{{ result.coverage.pct.toFixed(1) }}%</strong>
            ({{ result.coverage.hit }}/{{ result.coverage.total }} bins)
          </div>
        </Message>

        <Message v-if="error" severity="error" class="result-msg" :closable="false">
          {{ error }}
        </Message>
      </template>
    </Card>

    <!-- Danger Zone Card -->
    <Card class="control-card danger-card">
      <template #title>
        <div class="card-title-row danger-title">
          <i class="pi pi-exclamation-triangle card-title-icon" />
          Danger Zone
        </div>
      </template>
      <template #content>
        <p class="danger-desc">
          Reset all coverage data. This cannot be undone.
        </p>

        <Button
          label="Reset Coverage"
          icon="pi pi-trash"
          severity="danger"
          :loading="resetting"
          @click="confirmReset"
        />

        <Message v-if="resetDone" severity="success" class="result-msg" :closable="false">
          Coverage has been reset.
        </Message>

        <ConfirmDialog />
      </template>
    </Card>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive } from 'vue'
import Card from 'primevue/card'
import Button from 'primevue/button'
import InputNumber from 'primevue/inputnumber'
import ToggleButton from 'primevue/togglebutton'
import Tag from 'primevue/tag'
import Message from 'primevue/message'
import ConfirmDialog from 'primevue/confirmdialog'
import { useConfirm } from 'primevue/useconfirm'
import { api } from '@/api/client'
import type { GenerateResponse } from '@/types'

const confirm = useConfirm()

const allExtensions = ['M', 'A', 'F', 'D', 'C']

const form = reactive({
  count: 10,
  lengthMin: 5,
  lengthMax: 50
})

const extEnabled = reactive<Record<string, boolean>>({
  M: false, A: false, F: false, D: false, C: false
})

const loading   = ref(false)
const error     = ref<string | null>(null)
const result    = ref<GenerateResponse | null>(null)
const resetting = ref(false)
const resetDone = ref(false)

async function doGenerate() {
  loading.value = true
  error.value   = null
  result.value  = null
  try {
    const enabledExts = allExtensions.filter(e => extEnabled[e])
    const res = await api.generate({
      extensions: ['RV64I', ...enabledExts],
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

function confirmReset() {
  confirm.require({
    message: 'Are you sure you want to reset all coverage data? This cannot be undone.',
    header: 'Reset Coverage',
    icon: 'pi pi-exclamation-triangle',
    rejectLabel: 'Cancel',
    acceptLabel: 'Reset',
    acceptClass: 'p-button-danger',
    accept: doReset
  })
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

<style scoped>
.control-view {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1rem;
  max-width: 1000px;
}

.control-card { width: 100%; }

.card-title-row {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.card-title-icon { font-size: 1.1rem; }

.danger-title { color: #ef4444; }

.form-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 1rem;
  margin-bottom: 1.25rem;
}

.form-field {
  display: flex;
  flex-direction: column;
  gap: 0.4rem;
}

.field-label {
  font-size: 0.85rem;
  font-weight: 600;
  opacity: 0.7;
}

.field-input { width: 100%; }

.extensions-section {
  margin-bottom: 1.25rem;
}

.extensions-row {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin-top: 0.5rem;
  align-items: center;
}

.ext-fixed { font-size: 0.8rem; opacity: 0.6; }
.ext-toggle { font-size: 0.82rem; }

.generate-btn { width: 100%; margin-bottom: 1rem; }

.result-msg { margin-top: 0.75rem; }

.result-content {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  flex-wrap: wrap;
}

.danger-desc {
  margin: 0 0 1rem;
  opacity: 0.7;
  font-size: 0.9rem;
}
</style>
