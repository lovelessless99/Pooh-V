<template>
  <div :class="{ dark: dark }" class="app-root">
    <header class="app-header">
      <div class="header-brand">
        <span class="brand-icon">🐻</span>
        <span class="brand-text">Pooh-V</span>
      </div>

      <nav class="header-nav">
        <RouterLink to="/coverage" class="nav-link">Coverage</RouterLink>
        <RouterLink to="/bandit" class="nav-link">Bandit</RouterLink>
        <RouterLink to="/control" class="nav-link">Control</RouterLink>
        <RouterLink to="/scenarios" class="nav-link">Scenarios</RouterLink>
      </nav>

      <div class="header-actions">
        <button class="theme-toggle" @click="toggleDark" :title="dark ? 'Switch to Light' : 'Switch to Dark'">
          <i :class="dark ? 'pi pi-sun' : 'pi pi-moon'" />
        </button>
      </div>
    </header>

    <main class="app-main">
      <RouterView />
    </main>

    <footer class="app-footer">
      <span class="sse-status">
        <span class="sse-dot" :class="connected ? 'sse-dot--connected' : 'sse-dot--disconnected'" />
        {{ connected ? 'Live' : 'Disconnected' }}
      </span>
      <span class="footer-label">Pooh-V RISC-V Dashboard</span>
    </footer>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { RouterLink, RouterView } from 'vue-router'
import { useSSE } from './composables/useSSE'

// useSSE does not expose connected — track it ourselves via a simple heuristic
const connected = ref(false)

// Patch: track SSE state by overriding EventSource open/error at app level
// Since useSSE doesn't expose connected, we detect via window EventSource events
onMounted(() => {
  // Listen for any EventSource connecting to /api/stream
  const OriginalEventSource = window.EventSource
  window.EventSource = class extends OriginalEventSource {
    constructor(url: string | URL, init?: EventSourceInit) {
      super(url, init)
      const urlStr = url.toString()
      if (urlStr.includes('/api/stream')) {
        this.addEventListener('open', () => { connected.value = true })
        this.addEventListener('error', () => { connected.value = false })
      }
    }
  } as typeof EventSource
})

// Initialize SSE
useSSE()

const dark = ref(false)

function toggleDark() {
  dark.value = !dark.value
  document.documentElement.classList.toggle('dark', dark.value)
  localStorage.setItem('theme', dark.value ? 'dark' : 'light')
}

onMounted(() => {
  dark.value = localStorage.getItem('theme') === 'dark'
  document.documentElement.classList.toggle('dark', dark.value)
})
</script>

<style>
/* Reset */
*, *::before, *::after { box-sizing: border-box; }
body { margin: 0; padding: 0; font-family: var(--p-font-family, sans-serif); }

/* App root — fill viewport */
.app-root {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  background: var(--p-surface-100);
  color: var(--p-text-color);
  transition: background 0.2s, color 0.2s;
}

.dark .app-root {
  background: var(--p-surface-900);
}

/* Header */
.app-header {
  display: flex;
  align-items: center;
  gap: 1.5rem;
  padding: 0.75rem 1.5rem;
  background: var(--p-primary-600, #4f46e5);
  color: #fff;
  box-shadow: 0 2px 8px rgba(0,0,0,0.15);
}

.header-brand {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  white-space: nowrap;
}

.brand-icon { font-size: 1.4rem; }
.brand-text { font-size: 1.2rem; font-weight: 700; letter-spacing: 0.03em; }

.header-nav {
  display: flex;
  align-items: center;
  gap: 0.25rem;
  flex: 1;
  justify-content: center;
}

.nav-link {
  color: rgba(255,255,255,0.85);
  text-decoration: none;
  padding: 0.4rem 0.9rem;
  border-radius: 6px;
  font-size: 0.9rem;
  font-weight: 500;
  transition: background 0.15s, color 0.15s;
}

.nav-link:hover {
  background: rgba(255,255,255,0.15);
  color: #fff;
}

.nav-link.router-link-active {
  background: rgba(255,255,255,0.25);
  color: #fff;
  font-weight: 700;
}

.header-actions {
  display: flex;
  align-items: center;
}

.theme-toggle {
  background: rgba(255,255,255,0.15);
  border: 1px solid rgba(255,255,255,0.25);
  color: #fff;
  border-radius: 8px;
  width: 2.2rem;
  height: 2.2rem;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  font-size: 1rem;
  transition: background 0.15s;
}

.theme-toggle:hover { background: rgba(255,255,255,0.3); }

/* Main content */
.app-main {
  flex: 1;
  padding: 1.5rem;
}

/* Footer */
.app-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0.5rem 1.5rem;
  background: var(--p-surface-200);
  border-top: 1px solid var(--p-surface-300);
  font-size: 0.78rem;
  color: var(--p-text-muted-color, #6b7280);
}

.dark .app-footer {
  background: var(--p-surface-800);
  border-color: var(--p-surface-700);
}

.sse-status {
  display: flex;
  align-items: center;
  gap: 0.4rem;
}

.sse-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
}

.sse-dot--connected { background: #22c55e; }
.sse-dot--disconnected { background: #ef4444; }

.footer-label { opacity: 0.6; }
</style>
