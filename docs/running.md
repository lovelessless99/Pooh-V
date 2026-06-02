# Running riscv-rig

## Development Mode (two terminals)

**Terminal 1 — Haskell backend:**
```bash
cabal run riscv-rig -- server --port 8080
```

**Terminal 2 — Vue3 frontend (hot reload):**
```bash
cd frontend
npm install       # first time only
npm run dev
```

Open http://localhost:5173 — Vite proxies `/api/*` to the Haskell backend on :8080.

---

## Production Mode (single port)

**Step 1: Build the frontend:**
```bash
cd frontend
npm run build     # outputs to frontend/dist/
cd ..
```

**Step 2: Start the backend (which also serves the frontend):**
```bash
cabal run riscv-rig -- server --port 8080
```

Open http://localhost:8080 — the same server serves both the API and the dashboard.

---

## Running Tests

**Haskell unit tests:**
```bash
cabal test riscv-rig-test --test-show-details=direct
```

**Frontend unit tests (Vitest):**
```bash
cd frontend
npm run test
```

**Frontend tests in watch mode:**
```bash
cd frontend
npm run test:watch
```

---

## Other Common Commands

**Print version:**
```bash
cabal run riscv-rig -- version
```

**Generate sequences (no server):**
```bash
# 10 random sequences, RV64I only
cabal run riscv-rig -- generate --count 10

# With extensions
cabal run riscv-rig -- generate --count 10 --ext A --ext M --ext F

# Reproducible with fixed seed
cabal run riscv-rig -- generate --seed 12345 --count 5
```
