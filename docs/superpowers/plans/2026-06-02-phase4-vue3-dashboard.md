# Phase 4: Vue3 Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Vue3 single-page dashboard that consumes the Phase 3 REST API, displays real-time coverage/bandit data via SSE, and provides interactive controls for generation and scenarios.

**Architecture:** Haskell backend gains a `GET /stream` SSE endpoint triggered by a `TVar Int` generation counter, and serves `frontend/dist/` static files from the same Warp port via `combineApps`. Vue3 frontend lives in `frontend/`, connects to `/api/*` via Vite dev proxy, uses Pinia stores updated by a `useSSE` composable, and renders four views with Chart.js charts.

**Tech Stack:** Haskell: `wai-extra >= 3.1` (SSE), `wai-app-static >= 3.1` (static serving). Frontend: Vue 3.4 + Vite 5 + TypeScript 5 + Pinia 2 + Chart.js 4 + vue-chartjs 5 + Axios 1.6 + Vitest 1.

---

## File Map

**Modified (Haskell):**
- `src/API/Types.hs` — add `ssGenCounter :: TVar Int` to `ServerState`, export `ServerState(..)`, add `SSEEvent` type
- `src/API/Server.hs` — add `"stream" :> Raw` to `RigAPI`, `handleStream` handler, extract `toBanditResponse` helper, increment counter in `handleGenerate`
- `app/CLI/Runner.hs` — add `combineApps`, update `runServer` to serve `frontend/dist/`
- `riscv-rig.cabal` — add `wai-extra` to library deps, `wai-app-static` + `wai` to executable deps
- `test/Test/API/Server.hs` — add 2 new tests: counter increment and SSEEvent JSON shape

**Created (Frontend):**
- `frontend/package.json`, `frontend/tsconfig.json`, `frontend/tsconfig.node.json`
- `frontend/vite.config.ts`, `frontend/index.html`
- `frontend/src/types.ts` — all TypeScript interfaces matching Haskell JSON field names
- `frontend/src/api/client.ts` — Axios wrapper for all 6 endpoints
- `frontend/src/stores/coverage.ts`, `frontend/src/stores/bandit.ts` — Pinia stores
- `frontend/src/stores/coverage.test.ts`, `frontend/src/stores/bandit.test.ts` — Vitest unit tests
- `frontend/src/composables/useSSE.ts` — EventSource lifecycle composable
- `frontend/src/composables/useSSE.test.ts` — Vitest test with mocked EventSource
- `frontend/src/views/CoverageView.vue` — Doughnut chart + missing bins list
- `frontend/src/views/BanditView.vue` — Horizontal bar chart sorted by priority
- `frontend/src/views/ControlView.vue` — Generate form + Reset button
- `frontend/src/views/ScenariosView.vue` — Scenario list + Run button
- `frontend/src/router/index.ts` — Vue Router 4 with hash history
- `frontend/src/App.vue` — Nav bar + `<RouterView>` + `useSSE()` mount
- `frontend/src/main.ts` — App bootstrap with Pinia + Router

**Created (Docs):**
- `docs/running.md` — all dev/prod/test commands

---

## Task 1: Haskell — SSE Types and Counter

**Files:**
- Modify: `src/API/Types.hs`
- Modify: `test/Test/API/Server.hs`

Add `ssGenCounter :: TVar Int` to `ServerState`, export all its fields, and add `SSEEvent` type (the payload pushed over SSE).

- [ ] **Step 1: Update `src/API/Types.hs`**

Replace the current `ServerState` definition and module header with the following (showing the full relevant diff):

```haskell
module API.Types
  ( GenerateRequest(..)
  , GenerateResponse(..)
  , CoverageResponse(..)
  , BanditResponse(..)
  , BinInfo(..)
  , ScenarioInfo(..)
  , ScenarioRunResponse(..)
  , SSEEvent(..)
  , ServerState(..)        -- now exports (..) so test can access fields
  , newServerState
  ) where

import Coverage.Accumulator  (CoverageAccumulator, newAccumulator)
import Coverage.Bandit       (BanditState, initBandit)
import Coverage.Types        (allCoverageBins)
import Generator.Types       (defaultConfig, GeneratorConfig)
import Data.Text             (Text)
import Data.Aeson            (ToJSON(..), FromJSON(..), genericToJSON, genericParseJSON,
                              genericToEncoding, defaultOptions, Options(..))
import GHC.Generics          (Generic)
import Control.Concurrent.STM (TVar, newTVarIO)
```

Add after the existing JSON instances (just before `data ServerState`):

```haskell
data SSEEvent = SSEEvent
  { evCoverage :: CoverageResponse
  , evBandit   :: BanditResponse
  } deriving (Show, Eq, Generic)

instance ToJSON   SSEEvent where
  toJSON     = genericToJSON     (mkOpts "ev")
  toEncoding = genericToEncoding (mkOpts "ev")
instance FromJSON SSEEvent where parseJSON = genericParseJSON (mkOpts "ev")
```

Replace the `ServerState` definition:

```haskell
data ServerState = ServerState
  { ssAccumulator :: CoverageAccumulator
  , ssBandit      :: TVar BanditState
  , ssConfig      :: GeneratorConfig
  , ssGenCounter  :: TVar Int          -- incremented by handleGenerate
  }

newServerState :: IO ServerState
newServerState = ServerState
  <$> newAccumulator
  <*> newTVarIO (initBandit allCoverageBins)
  <*> pure defaultConfig
  <*> newTVarIO 0
```

- [ ] **Step 2: Add 2 new test cases to `test/Test/API/Server.hs`**

Add these imports at the top:

```haskell
import Control.Concurrent.STM    (readTVarIO)
import qualified Data.ByteString.Lazy as LBS
```

Add these two test cases inside the `tests` testGroup:

```haskell
  , testCase "handleGenerate increments ssGenCounter" $ do
      state <- newServerState
      let req = GenerateRequest
            { grExtensions = [pack "RV64I"]
            , grCount      = 1
            , grMode       = pack "random"
            , grLengthMin  = 5
            , grLengthMax  = 10
            }
      before <- readTVarIO (ssGenCounter state)
      _ <- runHandler (handleGenerate state req)
      after  <- readTVarIO (ssGenCounter state)
      after @?= before + 1

  , testCase "SSEEvent JSON encodes coverage as 'coverage' key" $ do
      let ev = SSEEvent
                (CoverageResponse 5 100 5.0 [])
                (BanditResponse [])
      assertBool "encoded JSON contains key 'coverage'"
        ("\"coverage\"" `LBS.isInfixOf` encode ev)
```

Also add `SSEEvent` to the `API.Types` import line:

```haskell
import API.Types
```

(It already imports `API.Types` with everything; `SSEEvent` will be included automatically.)

- [ ] **Step 3: Build and run tests**

```powershell
cabal build riscv-rig
cabal test riscv-rig-test --test-show-details=direct 2>&1 | Select-Object -Last 8
```

Expected: build succeeds, all existing tests pass.

- [ ] **Step 4: Commit**

```powershell
git add src/API/Types.hs test/Test/API/Server.hs
git commit -m "feat: add ssGenCounter to ServerState + SSEEvent type"
```

---

## Task 2: Haskell — GET /stream SSE Endpoint

**Files:**
- Modify: `src/API/Server.hs`
- Modify: `riscv-rig.cabal`

Add the `"stream" :> Raw` endpoint to `RigAPI`, implement `handleStream` using `eventSourceAppIO`, extract `toBanditResponse` helper, and increment the counter in `handleGenerate`.

- [ ] **Step 1: Add `wai-extra` to `riscv-rig.cabal` library deps**

In the `library` stanza's `build-depends`, add after the `aeson` line:

```cabal
    , wai-extra       >= 3.1
    , wai             >= 3.3
    , tagged          >= 0.8
```

(`tagged` provides `Data.Tagged` for the `Raw` handler type; `wai` provides `Application`.)

- [ ] **Step 2: Update `src/API/Server.hs`**

Add these imports:

```haskell
import API.Types
import Network.Wai              (Application)
import Network.Wai.EventSource  (ServerEvent(..), eventSourceAppIO)
import Data.ByteString.Builder  (byteString, lazyByteString)
import Data.Aeson               (encode)
import Data.IORef               (newIORef, readIORef, writeIORef)
import Data.Tagged              (Tagged(..))
```

Note: `Data.Aeson (encode)` — check if already imported via `API.Types` re-exports. If not, add it directly. `bytestring` is already a cabal dep.

Extend `RigAPI` to add the stream endpoint:

```haskell
type RigAPI =
       "generate"  :> ReqBody '[JSON] GenerateRequest  :> Post '[JSON] GenerateResponse
  :<|> "coverage"  :> Get '[JSON] CoverageResponse
  :<|> "coverage"  :> "reset" :> Post '[JSON] NoContent
  :<|> "bandit"    :> Get '[JSON] BanditResponse
  :<|> "scenarios" :> Get '[JSON] [ScenarioInfo]
  :<|> "scenarios" :> Capture "name" Text :> "run" :> Post '[JSON] ScenarioRunResponse
  :<|> "stream"    :> Raw
```

Update `server` to wire the new handler:

```haskell
server :: ServerState -> Server RigAPI
server state =
       handleGenerate      state
  :<|> handleGetCoverage   state
  :<|> handleResetCoverage state
  :<|> handleGetBandit     state
  :<|> handleGetScenarios
  :<|> handleRunScenario   state
  :<|> handleStream        state
```

Add `handleStream` (after `handleRunScenario`):

```haskell
handleStream :: ServerState -> Tagged Handler Application
handleStream state = Tagged $ \req respond -> do
  lastRef <- newIORef =<< readTVarIO (ssGenCounter state)
  eventSourceAppIO (nextEvent lastRef) req respond
  where
    nextEvent lastRef = do
      last_ <- readIORef lastRef
      newCount <- atomically $ do
        c <- readTVar (ssGenCounter state)
        if c > last_ then return c else retry
      writeIORef lastRef newCount
      snap   <- snapshotCoverage (ssAccumulator state)
      bs     <- readTVarIO (ssBandit state)
      let evt = SSEEvent (toCoverageResponse snap) (toBanditResponse bs)
      return $ ServerEvent
        { eventName = Just (byteString "update")
        , eventId   = Nothing
        , eventData = [lazyByteString (encode evt)]
        }
```

Extract `toBanditResponse` as a top-level helper (currently the logic is inline in `handleGetBandit`). Replace `handleGetBandit` with:

```haskell
handleGetBandit :: ServerState -> Handler BanditResponse
handleGetBandit state = liftIO $ toBanditResponse <$> readTVarIO (ssBandit state)

toBanditResponse :: BanditState -> BanditResponse
toBanditResponse bs = BanditResponse { brBins = map toBinInfo (toAscList (bsParams bs)) }
  where
    toBinInfo (bin, BetaParams a b) = BinInfo
      { biName     = pack (show bin)
      , biAlpha    = a
      , biBeta     = b
      , biPriority = a / (a + b)
      }
```

Also add `readTVar` and `retry` to the STM import (they are already in `Control.Concurrent.STM`; ensure `readTVar` and `retry` are imported alongside `atomically`, `readTVarIO`, `modifyTVar'`):

```haskell
import Control.Concurrent.STM (atomically, readTVar, readTVarIO, modifyTVar', retry)
```

Add `SSEEvent` import from `API.Types` — it's already imported via `import API.Types`.

Update `handleGenerate` to increment the counter. Add this line at the very end of the `do` block, just before the `return`:

```haskell
  atomically $ modifyTVar' (ssGenCounter state) (+1)
  return GenerateResponse
    { grSeqs     = map (map (pack . show)) seqs
    , grCoverage = toCoverageResponse snap
    }
```

(The `return` was previously the last line; now `atomically $ modifyTVar' ...` comes before it.)

- [ ] **Step 3: Build and run tests**

```powershell
cabal build riscv-rig
cabal test riscv-rig-test --test-show-details=direct 2>&1 | Select-Object -Last 8
```

Expected: build succeeds. The new counter increment test should now PASS (138 tests total).

- [ ] **Step 4: Commit**

```powershell
git add src/API/Server.hs riscv-rig.cabal
git commit -m "feat: add GET /stream SSE endpoint; increment ssGenCounter on generate"
```

---

## Task 3: Haskell — combineApps Static Serving

**Files:**
- Modify: `app/CLI/Runner.hs`
- Modify: `riscv-rig.cabal`

Serve `frontend/dist/` as static files from the same Warp port. Route `/api/*` to Servant, everything else to `wai-app-static`.

- [ ] **Step 1: Add `wai-app-static` and `wai` to executable deps in `riscv-rig.cabal`**

In the `executable riscv-rig` stanza's `build-depends`, add:

```cabal
    , wai-app-static  >= 3.1
    , wai             >= 3.3
```

- [ ] **Step 2: Update `app/CLI/Runner.hs`**

Add these imports:

```haskell
import Network.Wai                     (Application, Request(..))
import Network.Wai.Application.Static  (staticApp, defaultWebAppSettings)
```

Replace `runServer` with:

```haskell
runServer :: ServerOptions -> IO ()
runServer opts = do
  state <- newServerState
  let apiApp     = serve rigAPI (server state)
      staticApp_ = staticApp (defaultWebAppSettings "frontend/dist")
      combined   = combineApps apiApp staticApp_
  putStrLn ("riscv-rig server listening on port " <> show (soPort opts))
  putStrLn ("Dashboard: http://localhost:" <> show (soPort opts))
  run (soPort opts) combined

combineApps :: Application -> Application -> Application
combineApps api static_ req respond =
  case pathInfo req of
    ("api":rest) -> api req { pathInfo = rest } respond
    _            -> static_ req respond
```

- [ ] **Step 3: Build**

```powershell
cabal build riscv-rig
```

Expected: builds with no warnings. (We cannot test static serving without `frontend/dist/`; that will be verified in the smoke test after Task 8.)

- [ ] **Step 4: Run full test suite to verify no regressions**

```powershell
cabal test riscv-rig-test --test-show-details=direct 2>&1 | Select-Object -Last 5
```

Expected: all 138 tests pass.

- [ ] **Step 5: Commit**

```powershell
git add app/CLI/Runner.hs riscv-rig.cabal
git commit -m "feat: serve frontend/dist via combineApps on same Warp port"
```

---

## Task 4: Frontend Scaffold

**Files (all new):**
- Create: `frontend/package.json`
- Create: `frontend/tsconfig.json`
- Create: `frontend/tsconfig.node.json`
- Create: `frontend/vite.config.ts`
- Create: `frontend/index.html`

Create the Vue3 + Vite + TypeScript project skeleton and install dependencies.

- [ ] **Step 1: Create `frontend/package.json`**

```json
{
  "name": "riscv-rig-dashboard",
  "version": "0.1.0",
  "scripts": {
    "dev": "vite",
    "build": "vue-tsc && vite build",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "dependencies": {
    "vue": "^3.4.0",
    "vue-router": "^4.3.0",
    "pinia": "^2.1.0",
    "axios": "^1.6.0",
    "chart.js": "^4.4.0",
    "vue-chartjs": "^5.3.0"
  },
  "devDependencies": {
    "@vitejs/plugin-vue": "^5.0.0",
    "vite": "^5.0.0",
    "typescript": "^5.3.0",
    "vue-tsc": "^2.0.0",
    "vitest": "^1.0.0",
    "@vue/test-utils": "^2.4.0",
    "jsdom": "^23.0.0"
  }
}
```

- [ ] **Step 2: Create `frontend/tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "preserve",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "paths": { "@/*": ["./src/*"] }
  },
  "include": ["src/**/*.ts", "src/**/*.vue"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

- [ ] **Step 3: Create `frontend/tsconfig.node.json`**

```json
{
  "compilerOptions": {
    "composite": true,
    "skipLibCheck": true,
    "module": "ESNext",
    "moduleResolution": "bundler",
    "allowSyntheticDefaultImports": true
  },
  "include": ["vite.config.ts"]
}
```

- [ ] **Step 4: Create `frontend/vite.config.ts`**

```typescript
/// <reference types="vitest" />
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath, URL } from 'node:url'

export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url))
    }
  },
  server: {
    proxy: {
      '/api': { target: 'http://localhost:8080', changeOrigin: true }
    }
  },
  test: {
    globals: true,
    environment: 'jsdom'
  }
})
```

- [ ] **Step 5: Create `frontend/index.html`**

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>RISC-V Rig Dashboard</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module" src="/src/main.ts"></script>
  </body>
</html>
```

- [ ] **Step 6: Install dependencies**

```powershell
cd frontend
npm install
```

Expected: `node_modules/` created, no errors.

- [ ] **Step 7: Commit**

```powershell
cd ..
git add frontend/package.json frontend/tsconfig.json frontend/tsconfig.node.json frontend/vite.config.ts frontend/index.html frontend/package-lock.json
git commit -m "feat: scaffold Vue3 + Vite + TypeScript frontend"
```

---

## Task 5: TypeScript Types + API Client + Pinia Stores

**Files (all new):**
- Create: `frontend/src/types.ts`
- Create: `frontend/src/api/client.ts`
- Create: `frontend/src/stores/coverage.ts`
- Create: `frontend/src/stores/bandit.ts`
- Create: `frontend/src/stores/coverage.test.ts`
- Create: `frontend/src/stores/bandit.test.ts`

All TypeScript interfaces match the Haskell aeson JSON field names exactly (e.g., `crHit` → `hit` after prefix stripping).

- [ ] **Step 1: Write the tests first — `frontend/src/stores/coverage.test.ts`**

```typescript
import { describe, it, expect, beforeEach } from 'vitest'
import { setActivePinia, createPinia } from 'pinia'
import { useCoverageStore } from './coverage'
import type { CoverageResponse } from '@/types'

describe('useCoverageStore', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('initializes with zeros and empty missing list', () => {
    const store = useCoverageStore()
    expect(store.hit).toBe(0)
    expect(store.total).toBe(0)
    expect(store.pct).toBe(0)
    expect(store.missing).toEqual([])
  })

  it('update() sets all fields from a CoverageResponse', () => {
    const store = useCoverageStore()
    const data: CoverageResponse = { hit: 10, total: 200, pct: 5.0, missing: ['ADD', 'SUB'] }
    store.update(data)
    expect(store.hit).toBe(10)
    expect(store.total).toBe(200)
    expect(store.pct).toBe(5.0)
    expect(store.missing).toEqual(['ADD', 'SUB'])
  })
})
```

- [ ] **Step 2: Write the tests first — `frontend/src/stores/bandit.test.ts`**

```typescript
import { describe, it, expect, beforeEach } from 'vitest'
import { setActivePinia, createPinia } from 'pinia'
import { useBanditStore } from './bandit'
import type { BanditResponse } from '@/types'

describe('useBanditStore', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('initializes with empty bins array', () => {
    const store = useBanditStore()
    expect(store.bins).toEqual([])
  })

  it('update() replaces the entire bins array', () => {
    const store = useBanditStore()
    const data: BanditResponse = {
      bins: [{ name: 'ADD', alpha: 1.5, beta: 2.0, priority: 0.43 }]
    }
    store.update(data)
    expect(store.bins).toHaveLength(1)
    expect(store.bins[0].name).toBe('ADD')
    expect(store.bins[0].priority).toBeCloseTo(0.43)
  })

  it('update() called twice keeps only the latest data', () => {
    const store = useBanditStore()
    store.update({ bins: [{ name: 'ADD', alpha: 1, beta: 1, priority: 0.5 }] })
    store.update({ bins: [] })
    expect(store.bins).toHaveLength(0)
  })
})
```

- [ ] **Step 3: Run tests to verify they fail (types and stores not yet implemented)**

```powershell
cd frontend
npx vitest run 2>&1 | Select-Object -Last 10
```

Expected: FAIL — `Cannot find module './coverage'` or similar.

- [ ] **Step 4: Create `frontend/src/types.ts`**

JSON field names come from Haskell's `mkOpts` prefix stripping (e.g., `crHit` → `hit`, `brBins` → `bins`).

```typescript
export interface CoverageResponse {
  hit: number
  total: number
  pct: number
  missing: string[]
}

export interface BinInfo {
  name: string
  alpha: number
  beta: number
  priority: number
}

export interface BanditResponse {
  bins: BinInfo[]
}

export interface GenerateRequest {
  extensions: string[]
  count: number
  mode: string
  lengthMin: number
  lengthMax: number
}

export interface GenerateResponse {
  seqs: string[][]
  coverage: CoverageResponse
}

export interface ScenarioInfo {
  name: string
  tags: string[]
  extensions: string[]
  description: string
}

export interface ScenarioRunResponse {
  sequence: string[]
  coverageHits: string[]
}

export interface SSEEvent {
  coverage: CoverageResponse
  bandit: BanditResponse
}
```

- [ ] **Step 5: Create `frontend/src/stores/coverage.ts`**

```typescript
import { defineStore } from 'pinia'
import type { CoverageResponse } from '@/types'

export const useCoverageStore = defineStore('coverage', {
  state: () => ({
    hit: 0,
    total: 0,
    pct: 0,
    missing: [] as string[]
  }),
  actions: {
    update(data: CoverageResponse) {
      this.hit     = data.hit
      this.total   = data.total
      this.pct     = data.pct
      this.missing = data.missing
    }
  }
})
```

- [ ] **Step 6: Create `frontend/src/stores/bandit.ts`**

```typescript
import { defineStore } from 'pinia'
import type { BanditResponse, BinInfo } from '@/types'

export const useBanditStore = defineStore('bandit', {
  state: () => ({
    bins: [] as BinInfo[]
  }),
  actions: {
    update(data: BanditResponse) {
      this.bins = data.bins
    }
  }
})
```

- [ ] **Step 7: Create `frontend/src/api/client.ts`**

```typescript
import axios from 'axios'
import type {
  GenerateRequest, GenerateResponse, CoverageResponse,
  BanditResponse, ScenarioInfo, ScenarioRunResponse
} from '@/types'

const BASE = '/api'

export const api = {
  generate: (req: GenerateRequest) =>
    axios.post<GenerateResponse>(`${BASE}/generate`, req),
  getCoverage: () =>
    axios.get<CoverageResponse>(`${BASE}/coverage`),
  resetCoverage: () =>
    axios.post(`${BASE}/coverage/reset`),
  getBandit: () =>
    axios.get<BanditResponse>(`${BASE}/bandit`),
  getScenarios: () =>
    axios.get<ScenarioInfo[]>(`${BASE}/scenarios`),
  runScenario: (name: string) =>
    axios.post<ScenarioRunResponse>(`${BASE}/scenarios/${name}/run`),
}
```

- [ ] **Step 8: Run tests — should pass now**

```powershell
npx vitest run 2>&1 | Select-Object -Last 10
```

Expected: `5 tests passed`.

- [ ] **Step 9: Commit**

```powershell
cd ..
git add frontend/src/types.ts frontend/src/api/client.ts frontend/src/stores/
git commit -m "feat: add TypeScript types, API client, and Pinia stores with tests"
```

---

## Task 6: useSSE Composable

**Files (all new):**
- Create: `frontend/src/composables/useSSE.ts`
- Create: `frontend/src/composables/useSSE.test.ts`

The `useSSE` composable opens an `EventSource` to `/api/stream` on mount, parses `update` events, and pushes data into the Pinia stores.

- [ ] **Step 1: Write the test first — `frontend/src/composables/useSSE.test.ts`**

```typescript
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import { setActivePinia, createPinia } from 'pinia'
import { defineComponent } from 'vue'
import { useCoverageStore } from '@/stores/coverage'
import { useBanditStore } from '@/stores/bandit'
import { useSSE } from './useSSE'

class MockEventSource {
  static lastInstance: MockEventSource | null = null
  listeners: Record<string, Array<(e: MessageEvent) => void>> = {}
  onerror: ((e: Event) => void) | null = null

  constructor(public url: string) {
    MockEventSource.lastInstance = this
  }

  addEventListener(type: string, handler: (e: MessageEvent) => void) {
    if (!this.listeners[type]) this.listeners[type] = []
    this.listeners[type].push(handler)
  }

  close() {}

  dispatch(type: string, data: unknown) {
    const event = new MessageEvent(type, { data: JSON.stringify(data) })
    this.listeners[type]?.forEach(h => h(event))
  }
}

vi.stubGlobal('EventSource', MockEventSource)

const TestWrapper = defineComponent({
  setup() { useSSE() },
  template: '<div />'
})

describe('useSSE', () => {
  beforeEach(() => {
    MockEventSource.lastInstance = null
  })

  it('creates EventSource pointing at /api/stream on mount', () => {
    const pinia = createPinia()
    setActivePinia(pinia)
    mount(TestWrapper, { global: { plugins: [pinia] } })
    expect(MockEventSource.lastInstance).not.toBeNull()
    expect(MockEventSource.lastInstance!.url).toBe('/api/stream')
  })

  it('registers an "update" event listener', () => {
    const pinia = createPinia()
    setActivePinia(pinia)
    mount(TestWrapper, { global: { plugins: [pinia] } })
    expect(MockEventSource.lastInstance!.listeners['update']).toBeDefined()
    expect(MockEventSource.lastInstance!.listeners['update']).toHaveLength(1)
  })

  it('dispatching update event updates coverage and bandit stores', () => {
    const pinia = createPinia()
    setActivePinia(pinia)
    mount(TestWrapper, { global: { plugins: [pinia] } })

    MockEventSource.lastInstance!.dispatch('update', {
      coverage: { hit: 7, total: 100, pct: 7.0, missing: ['ADD'] },
      bandit:   { bins: [{ name: 'SUB', alpha: 2, beta: 1, priority: 0.67 }] }
    })

    const coverage = useCoverageStore()
    const bandit   = useBanditStore()
    expect(coverage.hit).toBe(7)
    expect(bandit.bins).toHaveLength(1)
    expect(bandit.bins[0].name).toBe('SUB')
  })
})
```

- [ ] **Step 2: Run tests to verify failure**

```powershell
cd frontend
npx vitest run 2>&1 | Select-Object -Last 10
```

Expected: FAIL — `Cannot find module './useSSE'`.

- [ ] **Step 3: Create `frontend/src/composables/useSSE.ts`**

```typescript
import { onMounted, onUnmounted } from 'vue'
import { useCoverageStore } from '@/stores/coverage'
import { useBanditStore } from '@/stores/bandit'
import type { SSEEvent } from '@/types'

export function useSSE() {
  let es: EventSource | null = null
  const coverage = useCoverageStore()
  const bandit   = useBanditStore()

  onMounted(() => {
    es = new EventSource('/api/stream')
    es.addEventListener('update', (e: MessageEvent) => {
      const data = JSON.parse(e.data) as SSEEvent
      coverage.update(data.coverage)
      bandit.update(data.bandit)
    })
    es.onerror = () => {
      es?.close()
      setTimeout(() => {
        es = new EventSource('/api/stream')
      }, 3000)
    }
  })

  onUnmounted(() => es?.close())
}
```

- [ ] **Step 4: Run tests — should pass**

```powershell
npx vitest run 2>&1 | Select-Object -Last 10
```

Expected: `8 tests passed` (5 store tests + 3 SSE tests).

- [ ] **Step 5: Commit**

```powershell
cd ..
git add frontend/src/composables/
git commit -m "feat: add useSSE composable with Vitest tests"
```

---

## Task 7: CoverageView + BanditView

**Files (all new):**
- Create: `frontend/src/views/CoverageView.vue`
- Create: `frontend/src/views/BanditView.vue`

Both views read from Pinia stores and render Chart.js charts. SSE updates automatically re-render via reactivity.

- [ ] **Step 1: Create `frontend/src/views/CoverageView.vue`**

```vue
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
```

- [ ] **Step 2: Create `frontend/src/views/BanditView.vue`**

```vue
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
```

- [ ] **Step 3: Verify TypeScript type-checks clean**

```powershell
cd frontend
npx vue-tsc --noEmit 2>&1 | Select-Object -Last 10
```

Expected: no errors (there will be errors if App.vue / router / main.ts don't exist yet; that's OK — the type-check errors are from missing files not from these views).

- [ ] **Step 4: Commit**

```powershell
cd ..
git add frontend/src/views/CoverageView.vue frontend/src/views/BanditView.vue
git commit -m "feat: add CoverageView (doughnut chart) and BanditView (bar chart)"
```

---

## Task 8: ControlView + ScenariosView

**Files (all new):**
- Create: `frontend/src/views/ControlView.vue`
- Create: `frontend/src/views/ScenariosView.vue`

Interactive views: generate form with POST /generate, reset button, scenarios list with Run button.

- [ ] **Step 1: Create `frontend/src/views/ControlView.vue`**

```vue
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
```

- [ ] **Step 2: Create `frontend/src/views/ScenariosView.vue`**

```vue
<template>
  <div class="view">
    <h2>Scenarios</h2>
    <p v-if="loading">Loading…</p>
    <ul v-else>
      <li v-for="s in scenarios" :key="s.name" style="margin-bottom:1rem">
        <strong>{{ s.name }}</strong>
        <span v-if="s.tags.length"> [{{ s.tags.join(', ') }}]</span>
        <span v-if="s.extensions.length"> — {{ s.extensions.join(', ') }}</span>
        <p style="margin:0.2rem 0">{{ s.description }}</p>
        <button @click="doRun(s.name)" :disabled="running === s.name">
          {{ running === s.name ? 'Running…' : 'Run' }}
        </button>
        <div v-if="runResults[s.name]">
          <small>Hits: {{ runResults[s.name].coverageHits.join(', ') || 'none' }}</small>
        </div>
      </li>
    </ul>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { api } from '@/api/client'
import type { ScenarioInfo, ScenarioRunResponse } from '@/types'

const scenarios  = ref<ScenarioInfo[]>([])
const loading    = ref(true)
const running    = ref<string | null>(null)
const runResults = ref<Record<string, ScenarioRunResponse>>({})

onMounted(async () => {
  try {
    const res = await api.getScenarios()
    scenarios.value = res.data
  } finally {
    loading.value = false
  }
})

async function doRun(name: string) {
  running.value = name
  try {
    const res = await api.runScenario(name)
    runResults.value[name] = res.data
  } finally {
    running.value = null
  }
}
</script>
```

- [ ] **Step 3: Commit**

```powershell
cd ..
git add frontend/src/views/ControlView.vue frontend/src/views/ScenariosView.vue
git commit -m "feat: add ControlView (generate form) and ScenariosView (scenario list + run)"
```

---

## Task 9: App.vue + Router + main.ts

**Files:**
- Create: `frontend/src/router/index.ts`
- Create (final): `frontend/src/App.vue`
- Create (final): `frontend/src/main.ts`

Wire everything together: router with four routes, App.vue with nav + `useSSE()`, main.ts bootstrapping Pinia + Router.

- [ ] **Step 1: Create `frontend/src/router/index.ts`**

Hash history avoids 404s when `wai-app-static` serves unknown paths in production.

```typescript
import { createRouter, createWebHashHistory } from 'vue-router'
import CoverageView  from '@/views/CoverageView.vue'
import BanditView    from '@/views/BanditView.vue'
import ControlView   from '@/views/ControlView.vue'
import ScenariosView from '@/views/ScenariosView.vue'

const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    { path: '/',           redirect: '/coverage' },
    { path: '/coverage',   component: CoverageView  },
    { path: '/bandit',     component: BanditView    },
    { path: '/control',    component: ControlView   },
    { path: '/scenarios',  component: ScenariosView },
  ]
})

export default router
```

- [ ] **Step 2: Create `frontend/src/App.vue`**

`useSSE()` is called here so SSE runs for the entire app lifetime regardless of active route.

```vue
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
```

- [ ] **Step 3: Create `frontend/src/main.ts`**

```typescript
import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'

createApp(App)
  .use(createPinia())
  .use(router)
  .mount('#app')
```

- [ ] **Step 4: Run the Vitest suite to verify all tests still pass**

```powershell
cd frontend
npx vitest run 2>&1 | Select-Object -Last 5
```

Expected: `8 tests passed`.

- [ ] **Step 5: Run the production build**

```powershell
npm run build 2>&1 | Select-Object -Last 10
```

Expected: `dist/` created, no errors. (`vue-tsc` type-checks first, then Vite builds.)

- [ ] **Step 6: Commit**

```powershell
cd ..
git add frontend/src/router/ frontend/src/App.vue frontend/src/main.ts
git commit -m "feat: wire Vue Router, App.vue nav, and main.ts bootstrap"
```

---

## Task 10: docs/running.md

**Files:**
- Create: `docs/running.md`

Document every command needed to run, build, test, and use riscv-rig.

- [ ] **Step 1: Create `docs/running.md`**

```markdown
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

**Start server on a custom port:**
```bash
cabal run riscv-rig -- server --port 9090
```

**Run co-simulation (requires Spike):**
```bash
cabal run riscv-rig -- run --spike /path/to/spike --rounds 5
```
```

- [ ] **Step 2: Commit**

```powershell
git add docs/running.md
git commit -m "docs: add running.md with dev/prod/test/CLI commands"
```

---

## Final Smoke Test

After all 10 tasks are complete:

- [ ] **Build frontend for production:**

```powershell
cd frontend
npm run build
cd ..
```

- [ ] **Start the Haskell server:**

```powershell
cabal run riscv-rig -- server --port 8080
```

- [ ] **Open http://localhost:8080 in a browser.**

Expected:
1. Dashboard loads — nav shows Coverage / Bandit / Control / Scenarios
2. Click Control → set count to 5 → click Generate → coverage % increases
3. Click Coverage → doughnut chart shows hit vs missing
4. Click Bandit → bar chart shows bins sorted by priority
5. Coverage and Bandit pages update automatically after Generate (SSE)
6. Click Scenarios → list appears → click Run on one scenario → hit bins shown

- [ ] **Run full Haskell test suite one final time:**

```powershell
cabal test riscv-rig-test --test-show-details=direct 2>&1 | Select-Object -Last 5
```

Expected: `138 tests passed`.
