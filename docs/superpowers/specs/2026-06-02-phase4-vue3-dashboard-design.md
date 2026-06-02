# Phase 4: Vue3 Dashboard — Design Spec
# Phase 4：Vue3 儀表板設計規格

---

## Goal / 目標

**EN:** Build a Vue3 single-page application that consumes the Phase 3 REST API and provides both real-time monitoring (coverage and bandit state update automatically via SSE) and interactive control (trigger generation, reset coverage, run scenarios).

**ZH:** 建立一個 Vue3 單頁應用程式，消費 Phase 3 REST API，同時提供即時監控（coverage 和 bandit 狀態透過 SSE 自動更新）和互動控制（觸發生成、重置 coverage、執行 scenarios）。

---

## Background / 背景

**EN:** Phase 3 delivered a Servant REST API with 6 endpoints, a Thompson Sampling bandit, and a coverage classifier. The backend is complete. Phase 4 adds a browser-based frontend that makes all backend functionality visible and interactive without needing CLI or curl.

**ZH:** Phase 3 交付了含 6 個 endpoint 的 Servant REST API、Thompson Sampling bandit 和 coverage classifier。後端已完整。Phase 4 加入以瀏覽器為基礎的前端，讓所有後端功能無需 CLI 或 curl 即可可視化和互動。

---

## Architecture / 架構

```
riscv-rig/
├── src/API/
│   ├── Server.hs     ← 新增 GET /stream SSE endpoint
│   └── Types.hs      ← 新增 SSEEvent type + ssGenCounter TVar
├── frontend/                    ← 全新 Vue3 app
│   ├── src/
│   │   ├── views/
│   │   │   ├── CoverageView.vue
│   │   │   ├── BanditView.vue
│   │   │   ├── ControlView.vue
│   │   │   └── ScenariosView.vue
│   │   ├── stores/
│   │   │   ├── coverage.ts      (Pinia)
│   │   │   └── bandit.ts        (Pinia)
│   │   ├── api/
│   │   │   └── client.ts        (Axios wrapper)
│   │   ├── composables/
│   │   │   └── useSSE.ts        (EventSource 訂閱)
│   │   ├── App.vue
│   │   └── main.ts
│   ├── vite.config.ts           (dev proxy /api → :8080)
│   ├── package.json
│   └── dist/                    (build 產物，gitignored)
├── app/CLI/Runner.hs            ← server 啟動時 serve frontend/dist/
├── riscv-rig.cabal              ← 新增 wai-extra, wai-app-static
└── docs/running.md              ← 新增，所有執行指令
```

### Data Flow / 資料流

```
使用者按「Generate」
    → POST /api/generate
    → Haskell 生成序列、更新 coverage + bandit
    → atomically $ modifyTVar' ssGenCounter (+1)
    → SSE handler 偵測到 counter 變化
    → 推送 SSEEvent{coverage, banditSummary} 給所有訂閱者
    → useSSE.ts 收到 event → 更新 Pinia stores
    → Coverage / Bandit 圖表自動重繪
```

---

## Component A: Backend SSE Endpoint / 後端 SSE Endpoint

### A1: ServerState 新增 generation counter

```haskell
-- src/API/Types.hs
data ServerState = ServerState
  { ssAccumulator :: CoverageAccumulator
  , ssBandit      :: TVar BanditState
  , ssConfig      :: GeneratorConfig
  , ssGenCounter  :: TVar Int    -- ← 新增，generate 後 +1
  }

newServerState :: IO ServerState
newServerState = ServerState
  <$> newAccumulator
  <*> newTVarIO (initBandit allCoverageBins)
  <*> pure defaultConfig
  <*> newTVarIO 0               -- ← 初始值 0
```

### A2: SSEEvent type

```haskell
-- src/API/Types.hs
data SSEEvent = SSEEvent
  { evCoverage :: CoverageResponse   -- hit/total/pct/missing
  , evBandit   :: BanditResponse     -- bins with α/β/priority
  } deriving (Show, Eq, Generic)

instance ToJSON SSEEvent where
  toJSON = genericToJSON defaultOptions
```

### A3: GET /stream endpoint

```haskell
-- src/API/Server.hs
-- 新增到 RigAPI type:
  :<|> "stream" :> Raw

-- handler:
handleStream :: ServerState -> Application
handleStream state req respond = do
  let counter = ssGenCounter state
  initialCount <- readTVarIO counter
  -- 等待 counter 變化（STM retry）
  -- 每次變化：讀 coverage + bandit，序列化成 SSE 格式，寫入 response
  eventSourceAppIO (generateEvents state initialCount) req respond

generateEvents :: ServerState -> Int -> IO ServerEvent
generateEvents state lastCount = do
  -- atomically 等待 counter > lastCount
  newCount <- atomically $ do
    c <- readTVar (ssGenCounter state)
    if c > lastCount then return c else retry
  snap   <- snapshotCoverage (ssAccumulator state)
  bandit <- readTVarIO (ssBandit state)
  let evt = SSEEvent (toCoverageResponse snap) (toBanditResponse bandit)
  return $ ServerEvent (Just "update") Nothing [fromString (encode evt)]
```

**依賴：** `wai-extra`（提供 `Network.Wai.EventSource`）

### A4: handleGenerate 更新 counter

```haskell
-- 在 handleGenerate 最後加：
atomically $ modifyTVar' (ssGenCounter state) (+1)
```

---

## Component B: Static File Serving / 靜態檔案服務

```haskell
-- app/CLI/Runner.hs
import Network.Wai.Application.Static (staticApp, defaultWebAppSettings)
import Network.Wai                    (Application)
import Network.Wai.Handler.Warp       (run)

runServer :: ServerOptions -> IO ()
runServer opts = do
  state <- newServerState
  let apiApp    = serve rigAPI (server state)
      staticApp_ = staticApp (defaultWebAppSettings "frontend/dist")
      combined   = combineApps apiApp staticApp_
  putStrLn ("riscv-rig server listening on port " <> show (soPort opts))
  putStrLn ("Dashboard: http://localhost:" <> show (soPort opts))
  run (soPort opts) combined

-- 路由規則：/api/* → apiApp，其他 → staticApp
combineApps :: Application -> Application -> Application
combineApps api static req respond =
  case pathInfo req of
    ("api":_) -> api req { pathInfo = tail (pathInfo req) } respond
    _         -> static req respond
```

**新增 cabal 依賴：**
```cabal
, wai-extra       >= 3.1
, wai-app-static  >= 3.1
```

---

## Component C: Vue3 Frontend

### Tech Stack / 技術棧

| 層 | 套件 | 版本 |
|---|---|---|
| 框架 | Vue 3 + Vite + TypeScript | vue ^3.4, vite ^5 |
| 路由 | Vue Router 4 | ^4.3 |
| 狀態管理 | Pinia | ^2.1 |
| 圖表 | Chart.js + vue-chartjs | chart.js ^4, vue-chartjs ^5 |
| HTTP | Axios | ^1.6 |
| SSE | 原生 EventSource | 無需套件 |

### C1: API Client (`src/api/client.ts`)

```typescript
import axios from 'axios'

const BASE = import.meta.env.DEV ? '/api' : '/api'

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

### C2: SSE Composable (`src/composables/useSSE.ts`)

```typescript
import { onMounted, onUnmounted } from 'vue'
import { useCoverageStore } from '@/stores/coverage'
import { useBanditStore } from '@/stores/bandit'

export function useSSE() {
  let es: EventSource | null = null
  const coverage = useCoverageStore()
  const bandit   = useBanditStore()

  onMounted(() => {
    es = new EventSource('/api/stream')
    es.addEventListener('update', (e: MessageEvent) => {
      const data = JSON.parse(e.data)
      coverage.update(data.coverage)
      bandit.update(data.bandit)
    })
    es.onerror = () => setTimeout(() => es?.close(), 3000)  // 自動重連
  })

  onUnmounted(() => es?.close())
}
```

### C3: Pinia Stores

```typescript
// src/stores/coverage.ts
export const useCoverageStore = defineStore('coverage', {
  state: () => ({ hit: 0, total: 0, pct: 0, missing: [] as string[] }),
  actions: {
    update(data: CoverageResponse) {
      this.hit     = data.hit
      this.total   = data.total
      this.pct     = data.pct
      this.missing = data.missing
    }
  }
})

// src/stores/bandit.ts
export const useBanditStore = defineStore('bandit', {
  state: () => ({ bins: [] as BinInfo[] }),
  actions: {
    update(data: BanditResponse) { this.bins = data.bins }
  }
})
```

### C4: 四個頁面

**CoverageView.vue**
- Doughnut chart（vue-chartjs）顯示 hit/total bins
- 進度條百分比
- 前 20 個未覆蓋 bins 列表

**BanditView.vue**
- 水平條狀圖，按 priority（α/(α+β)）由高到低排序
- 每個 bin 顯示 α、β、priority
- SSE 自動更新

**ControlView.vue**
- Generate 表單：count（default 10）、min/max length、extensions checkbox（M/A/F/D/C）
- Submit 觸發 POST /generate，顯示 loading 和結果
- Reset Coverage 按鈕

**ScenariosView.vue**
- 從 GET /scenarios 載入列表
- 每個 scenario 顯示 name、tags、extensions
- 「Run」按鈕觸發 POST /scenarios/:name/run，顯示命中的 bins

### C5: Vite 設定（dev proxy）

```typescript
// vite.config.ts
export default defineConfig({
  plugins: [vue()],
  server: {
    proxy: {
      '/api': { target: 'http://localhost:8080', changeOrigin: true }
    }
  }
})
```

---

## Component D: Documentation / 文件

### `docs/running.md`

記錄以下所有情境：

**開發模式（兩個 terminal）：**
```bash
# Terminal 1 — Haskell backend
cabal run riscv-rig -- server --port 8080

# Terminal 2 — Vue3 frontend (hot reload)
cd frontend
npm install
npm run dev
# 開啟 http://localhost:5173
```

**Production build：**
```bash
# 1. build 前端
cd frontend
npm run build           # 產出 frontend/dist/

# 2. 啟動 backend（同時 serve 前端靜態檔）
cd ..
cabal run riscv-rig -- server --port 8080
# 開啟 http://localhost:8080
```

**執行測試：**
```bash
# Haskell 測試
cabal test riscv-rig-test

# 前端單元測試
cd frontend
npm run test
```

**其他常用指令：**
```bash
# 查看版本
cabal run riscv-rig -- version

# 只生成（不開 server）
cabal run riscv-rig -- generate --count 10 --ext A --ext M

# 指定 seed（reproducible）
cabal run riscv-rig -- generate --seed 12345 --count 5
```

---

## New Dependencies / 新增依賴

### Haskell (riscv-rig.cabal)
```cabal
-- library build-depends:
, wai-extra       >= 3.1   -- SSE (Network.Wai.EventSource)
, wai-app-static  >= 3.1   -- serve frontend/dist/
, bytestring      >= 0.11  -- already present
```

### Frontend (frontend/package.json)
```json
{
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
    "vitest": "^1.0.0",
    "@vue/test-utils": "^2.4.0"
  }
}
```

---

## Testing Strategy / 測試策略

**EN:**
- Haskell: Unit test for SSE counter — verify `ssGenCounter` increments after `handleGenerate`; verify SSE event contains valid `CoverageResponse`.
- Frontend: Vitest unit tests for Pinia stores — mock API responses, verify store state updates correctly.
- Frontend: Vitest unit test for `useSSE` composable — mock `EventSource`, verify store updates on message.
- E2E: Manual smoke test — start server + dev frontend, click Generate, verify charts update.

**ZH:**
- Haskell：SSE counter unit test——驗證 `handleGenerate` 後 `ssGenCounter` +1；驗證 SSE event 包含合法 `CoverageResponse`。
- 前端：Pinia stores 的 Vitest unit test——mock API responses，驗證 store 狀態正確更新。
- 前端：`useSSE` composable 的 Vitest unit test——mock `EventSource`，驗證收到訊息後 store 更新。
- E2E：手動 smoke test——啟動 server + dev frontend，按 Generate，確認圖表更新。

---

## Key Design Decisions / 關鍵設計決策

1. **SSE over WebSocket：** 資料流是單向的（server → client），SSE 足夠，比 WebSocket 少 ~200 行實作。
2. **Counter-based SSE trigger：** 用 `TVar Int` 當觸發點，STM `retry` 等待變化。比 broadcast channel 簡單，不需要 `stm-chans` 套件。
3. **同埠 serve 前後端（production）：** `combineApps` 按 path prefix 路由，不需要 nginx 或 reverse proxy。
4. **Pinia + vue-chartjs：** 官方推薦的 Vue3 狀態管理，Chart.js 對學習友善，不需要學 D3.js。
5. **Vite proxy（dev）：** 開發時前後端分開跑，Vite 自動 proxy `/api/*`，CORS 問題歸零。
6. **`/api` prefix routing：** Warp 根據 path 前綴決定交給 API handler 還是靜態檔案，前端所有 API 呼叫加 `/api/` 前綴。
