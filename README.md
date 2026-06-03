# Pooh-V — SMT 導向 RISC-V 隨機指令測試產生器

> 以 Haskell 實作，結合 Z3 SMT 求解器、Thompson Sampling Bandit 覆蓋率最佳化器，與 Spike 協同模擬驗證 RISC-V 處理器正確性。

🎞 **投影片**：[lovelessless99.github.io/Pooh-V](https://lovelessless99.github.io/Pooh-V/)

---

## 系統需求

| 工具 | 版本 | 說明 |
|------|------|------|
| GHC | 9.8.4 | Haskell 編譯器 |
| Cabal | 3.10+ | 套件管理 |
| Node.js | 20+ | 前端建置（建議 Windows 原生，非 snap） |
| Z3 | 4.12+ | SMT 求解器（選用，缺少時測試自動略過） |
| Spike | latest | RISC-V ISA 模擬器（選用，缺少時測試自動略過） |

---

## 下載

```bash
git clone https://github.com/lovelessless99/Pooh-V.git
cd Pooh-V
```

---

## 啟動環境

### 方式一：Windows（前端熱更新開發）

開兩個終端：

```powershell
# Terminal 1 — Haskell 後端
cabal run pooh-v -- server --port 8080

# Terminal 2 — Vue3 前端（Vite dev server，有熱更新）
cd frontend
npm install
npm run dev
```

開瀏覽器 → `http://localhost:5173`

Vite 會自動把 `/api/...` 請求 proxy 到後端 8080。

---

### 方式二：WSL Linux（接近真實部署環境）

> Node.js 在 WSL 中需用 nvm 安裝，不可用 snap（snap 版本不支援 WSL）。

**Step 1 — Windows 先建置前端：**
```powershell
cd frontend
npm install
npm run build
```

**Step 2 — WSL 複製並啟動：**
```bash
# 複製 dist 到 WSL 的工作目錄
cp -r /mnt/c/Users/<你的使用者名稱>/OneDrive/Desktop/plan/riscv-rig/frontend/dist ~/pooh-v/frontend/

# 重啟伺服器
pkill pooh-v 2>/dev/null; sleep 1
cd ~/pooh-v
$(find dist-newstyle -name "pooh-v" -type f -executable | head -1) server --port 8080
```

開瀏覽器 → `http://localhost:8080`

---

## CLI 使用方式

### 產生 ELF 測試檔（不執行模擬）

```bash
cabal run pooh-v -- generate \
  --ext M --ext A --ext F \
  --count 20 \
  --output ./output
```

| 參數 | 說明 |
|------|------|
| `--ext` | 啟用 ISA 擴充：M、A、F、D、C |
| `--count / -n` | 產生幾個序列（預設 10）|
| `--seed` | 固定亂數種子（可重現） |
| `--output / -o` | 輸出目錄（預設 `output/`）|

---

### 產生並用 Spike 協同模擬

```bash
cabal run pooh-v -- run \
  --ext M \
  --rounds 50 \
  --min-len 20 \
  --max-len 100 \
  --spike spike \
  --output ./output
```

| 參數 | 說明 |
|------|------|
| `--rounds / -n` | 執行幾輪（每輪產生 10 個序列）|
| `--min-len` | 序列最短指令數（預設 10）|
| `--max-len` | 序列最長指令數（預設 50）|
| `--spike` | Spike 執行檔路徑（預設 `spike`）|

每輪執行後會印出覆蓋率摘要，顯示哪些 coverage bin 已命中。

---

### 啟動 Dashboard 伺服器

```bash
cabal run pooh-v -- server --port 8080
```

REST API 端點：

| 路徑 | 方法 | 說明 |
|------|------|------|
| `/api/coverage` | GET | 取得當前覆蓋率快照 |
| `/api/bandit` | GET | 取得 Thompson Sampling bandit 狀態 |
| `/api/generate` | POST | 觸發一批指令序列產生 |
| `/api/events` | GET | SSE 串流，即時推送覆蓋率更新 |

---

## Dashboard 說明

開啟 `http://localhost:8080`（或開發時 `http://localhost:5173`）。

| 頁面 | 說明 |
|------|------|
| **Coverage** | 覆蓋率總覽：已命中 / 未命中的 coverage bin，Doughnut 圖表 |
| **Bandit** | Thompson Sampling 各 bin 的 α/β 參數與優先順序 |
| **Control** | 手動調整生成參數，選擇 ISA 擴充，觸發重置 |
| **Scenarios** | 內建場景列表，可一鍵執行 |

右上角可切換深色 / 淺色主題，設定會記憶在 localStorage。

---

## 執行測試

```bash
# 全部測試（Z3 / Spike 不在 PATH 時自動略過）
cabal test

# 只跑單元測試
cabal test pooh-v-test --test-show-details=direct

# 只跑整合測試（需要 Spike）
cabal test pooh-v-integration --test-show-details=direct
```

目前測試數量：**141 個**（138 單元 + 3 整合），Z3 與 Spike 缺席時全部 pass。

---

## 文件索引

### 設計規格（Specs）

| 文件 | 說明 |
|------|------|
| [`docs/superpowers/specs/2026-05-21-riscv-rig-design.md`](docs/superpowers/specs/2026-05-21-riscv-rig-design.md) | 原始系統設計規格（整體架構、六階段計畫）|
| [`docs/superpowers/specs/2026-05-26-nix-packaging-design.md`](docs/superpowers/specs/2026-05-26-nix-packaging-design.md) | Nix 打包設計 |
| [`docs/superpowers/specs/2026-06-02-phase3-coverage-optimizer-design.md`](docs/superpowers/specs/2026-06-02-phase3-coverage-optimizer-design.md) | Phase 3 覆蓋率最佳化設計（Bandit + SSE API）|
| [`docs/superpowers/specs/2026-06-02-phase4-vue3-dashboard-design.md`](docs/superpowers/specs/2026-06-02-phase4-vue3-dashboard-design.md) | Phase 4 Vue3 Dashboard 設計 |

### 實作計畫（Plans）

| 文件 | 說明 |
|------|------|
| [`docs/superpowers/plans/2026-05-22-riscv-rig-phase1.md`](docs/superpowers/plans/2026-05-22-riscv-rig-phase1.md) | Phase 1：RV64I+M、Z3、ELF、Spike CoSim |
| [`docs/superpowers/plans/2026-06-01-phase2-complete-isa-scenario.md`](docs/superpowers/plans/2026-06-01-phase2-complete-isa-scenario.md) | Phase 2：RV64A/F/D/C 擴充 + Scenario 系統 |
| [`docs/superpowers/plans/2026-06-02-phase3-coverage-optimizer.md`](docs/superpowers/plans/2026-06-02-phase3-coverage-optimizer.md) | Phase 3：覆蓋率導向生成 + Thompson Sampling + REST API |
| [`docs/superpowers/plans/2026-06-02-phase4-vue3-dashboard.md`](docs/superpowers/plans/2026-06-02-phase4-vue3-dashboard.md) | Phase 4：PrimeVue Dashboard |
| [`docs/superpowers/plans/2026-05-27-nix-packaging.md`](docs/superpowers/plans/2026-05-27-nix-packaging.md) | Nix flake 打包 |

### 其他文件

- [`docs/roadmap.md`](docs/roadmap.md) — 六階段開發路線圖
- [`docs/running.md`](docs/running.md) — 執行細節
- [`docs/nix-setup.md`](docs/nix-setup.md) — Nix 環境建置

---

## Constraint 精隨

Constraint 是用 **Z3 SMT 求解器**解出合法指令參數的約束條件。定義在 `src/Constraint/` 下：

```
Constraint/
  Types.hs       -- ConstraintDef、ConstraintSet、SymState（符號暫存器）
  Solver.hs      -- 呼叫 SBV/Z3 求解，傳回 InstrParams
  Library.hs     -- 內建 constraint 函式庫
  Combinators.hs -- mergeConstraints 等組合子
```

### 內建 Constraints（`Constraint.Library`）

| Constraint | 作用 | Tag |
|-----------|------|-----|
| `rdNotZero` | `rd != x0`，避免寫入零暫存器 | `Register, SafetyNet` |
| `rs1NotZero` | `rs1 != x0` | `Register` |
| `rs2NotZero` | `rs2 != x0` | `Register` |
| `rdNotSameAsRs1` | `rd != rs1`，測試 fusion boundary | `Register` |
| `alignedImm n` | immediate 必須 n-byte 對齊 | `Memory, Alignment` |
| `immInRange lo hi` | immediate 在 `[lo, hi]` 範圍內 | `Memory` |
| `branchImmEven` | branch offset 必須 2-byte 對齊 | `Branch` |
| `noLoadUseHazard` | `rs1 != rd`，避免 load-use hazard | `Performance` |

### 運作原理

```
InstrTemplate  →  ConstraintSet  →  Z3 求解  →  InstrParams
（要生成什麼指令）   （有哪些限制）     （找合法值）   （rd=3, rs1=5, imm=8）
```

Z3 不在 PATH 時，Solver 直接 fallback 到隨機採樣，測試仍可執行。

---

## Scenario 精隨

Scenario 是**有結構的多相段測試腳本**，用來測試超出單一隨機指令能覆蓋的複雜行為。定義在 `src/Scenario/` 下：

```
Scenario/
  Types.hs              -- ScenarioSpec、ScenarioPhase、Directive、Event
  Registry.hs           -- allScenarios 列表
  Builtin/
    LrscInterrupt.hs    -- 內建場景：LR/SC + Timer Interrupt
```

### 目前內建 Scenario

#### `lrsc-timer-interrupt`

測試 **LR.D / SC.D 在 Timer Interrupt 中斷後 reservation 是否正確失效**：

```
Phase 1: setup         — 空（可放初始化指令）
Phase 2: lr-acquire    — 發出 LR.D x1, (x2)，後接 0~3 個隨機指令
Phase 3: interrupt     — 注入 Timer Interrupt（模擬外部中斷）
Phase 4: sc-verify     — 發出 SC.D x1, x2, (x1)，SC 應該失敗（rd=1）
```

覆蓋目標：`LrscPair`（LR+SC 配對）+ `LrscFail`（SC 確實失敗）

Tags：`Atomic, Interrupt, Privileged, CornerCase`

### Scenario 結構

```haskell
ScenarioSpec
  { sName       -- 唯一識別名稱
  , sTags       -- 分類標籤（Atomic / Interrupt / ...）
  , sExtensions -- 需要哪些 ISA 擴充
  , sClaims     -- 執行後應命中哪些 coverage bin
  , sPhases     -- 多個 ScenarioPhase，依序執行
  }

ScenarioPhase
  { spConstraints -- Z3 constraints（此 phase 的指令需滿足）
  , spDirectives  -- EmitInstr（固定指令）/ RandomN n m（隨機 n~m 個）
  , spEvents      -- InjectTimerInterrupt 等事件
  }
```

新增 Scenario 只需在 `Builtin/` 新增一個 `spec :: ScenarioSpec`，並在 `Registry.hs` 的 `allScenarios` 加入即可。

---

## 專案架構

```
src/
  Core/         ISA 模型（指令 ADT、encode/decode、CSR）
  Constraint/   Z3 約束求解
  Generator/    隨機 + 導向指令序列生成
  Coverage/     覆蓋率 bin 定義、分類、Thompson Sampling Bandit
  Scenario/     結構化場景腳本
  CoSim/        Spike / Sail 協同模擬
  ELF/          ELF64 檔案輸出
  API/          Servant REST API + SSE

app/            CLI 進入點
frontend/       Vue3 + PrimeVue Dashboard
test/           HUnit + Hedgehog 測試
docs/           規格、計畫、投影片
```

---

## 開發路線圖

- [x] Phase 1 — RV64I+M、Z3、ELF、Spike CoSim
- [x] Phase 2 — RV64A/F/D/C、Scenario 系統
- [x] Phase 3 — 覆蓋率導向生成、Thompson Sampling、REST API
- [x] Phase 4 — PrimeVue Dashboard
- [ ] Phase 5 — ELF 改進、Sail CoSim oracle
- [ ] Phase 6 — RVV Vector 擴充（獨立子專案）
