<template>
  <header>
    <span class="brand">🐻 Pooh-V</span>
    <nav>
      <RouterLink to="/coverage">🍯 Coverage</RouterLink>
      <RouterLink to="/bandit">🌳 Bandit</RouterLink>
      <RouterLink to="/control">⚙️ Control</RouterLink>
      <RouterLink to="/scenarios">🗺️ Scenarios</RouterLink>
    </nav>
  </header>
  <main>
    <RouterView />
  </main>
</template>

<script setup lang="ts">
import { useSSE } from '@/composables/useSSE'
useSSE()
</script>

<style>
body { font-family: sans-serif; margin: 0; padding: 0; background: #fffbeb; }
header { background: #78350f; color: white; padding: 0.75rem 1.5rem; display: flex; align-items: center; gap: 2rem; }
.brand { font-size: 1.2rem; font-weight: bold; color: #fef3c7; white-space: nowrap; }
nav a { color: #fde68a; text-decoration: none; margin-right: 1.5rem; }
nav a.router-link-active { color: #fef9c3; font-weight: bold; }
main { padding: 1.5rem; }
.view h2 { margin-top: 0; }
label { display: block; margin: 0.4rem 0; }
button { margin-top: 0.5rem; cursor: pointer; }
</style>
