<template>
  <header>
    <nav>
      <RouterLink to="/coverage">Coverage</RouterLink>
      <RouterLink to="/bandit">Bandit</RouterLink>
      <RouterLink to="/control">Control</RouterLink>
      <RouterLink to="/scenarios">Scenarios</RouterLink>
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
body { font-family: sans-serif; margin: 0; padding: 0; }
header { background: #1e293b; color: white; padding: 0.75rem 1.5rem; }
nav a { color: #93c5fd; text-decoration: none; margin-right: 1.5rem; }
nav a.router-link-active { color: white; font-weight: bold; }
main { padding: 1.5rem; }
.view h2 { margin-top: 0; }
label { display: block; margin: 0.4rem 0; }
button { margin-top: 0.5rem; cursor: pointer; }
</style>
