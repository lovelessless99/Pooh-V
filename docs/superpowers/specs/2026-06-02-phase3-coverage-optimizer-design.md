# Phase 3: Coverage-Guided Generation — Design Spec
# Phase 3：Coverage 導向生成設計規格

---

## Goal / 目標

**EN:** Implement a closed-loop coverage feedback engine. The system generates RISC-V instruction sequences, classifies which coverage bins they hit, uses a Thompson Sampling bandit to prioritise uncovered bins, and uses Z3 to generate sequences that target specific bins. A Servant REST API exposes all functionality to external tools and the future Vue3 dashboard.

**ZH:** 實作一個閉迴路 coverage feedback 引擎。系統生成 RISC-V 指令序列、分類命中了哪些 coverage bins、用 Thompson Sampling bandit 優先選擇未覆蓋的 bins、並用 Z3 生成針對特定 bin 的序列。Servant REST API 將所有功能暴露給外部工具和未來的 Vue3 dashboard。

---

## Background / 背景

**EN:** Phase 1 and Phase 2 built the ISA model, constraint solver, random generator, and coverage accumulator. The generator has three modes (`PureRandom`, `SolverDirected`, `Hybrid`) but only `PureRandom` is implemented. Coverage bins are defined but:
1. `allOpcodeBins` is a hand-written string list — silent drift when new instructions are added.
2. No code actually classifies a sequence into bins — `recordCoverage` requires the caller to compute bins manually.
3. The bandit and guided generator do not exist yet.

**ZH:** Phase 1 和 Phase 2 建立了 ISA 模型、constraint solver、random generator 和 coverage accumulator。Generator 有三種模式（`PureRandom`、`SolverDirected`、`Hybrid`）但只有 `PureRandom` 已實作。Coverage bins 已定義，但：
1. `allOpcodeBins` 是手寫字串列表——加新指令時靜悄悄地漂移。
2. 沒有任何程式碼自動把序列分類成 bins——`recordCoverage` 需要呼叫方手動計算。
3. Bandit 和 guided generator 尚不存在。

---

## Architecture / 架構

```
┌─────────────────────────────────────────────────────────────┐
│                    Feedback Loop (Sequential)                │
│                                                             │
│   BanditState ──sample──▶ target CoverageBin               │
│       ▲                         │                           │
│       │ update                  ▼                           │
│   [CoverageBin]          GuidedGenerator                    │
│       ▲                   (Z3 or Random)                    │
│       │                         │                           │
│   Classifier ◀─── [Instruction] (generated sequence)       │
│                                                             │
│   Accumulator ◀──────────────── [CoverageBin] (hits)       │
└─────────────────────────────────────────────────────────────┘

         ▲  REST API (Servant/Warp)  ▲
         │  POST /generate           │
         │  GET  /coverage           │
         │  GET  /bandit             │
         └───────────────────────────┘
```

**EN:** The loop is sequential (single-threaded). One sequence is generated, classified, and used to update the bandit before the next iteration. This keeps the design simple and testable. Concurrency can be added in a later phase.

**ZH:** 迴路是循序執行（單執行緒）。每次生成一個序列、分類、更新 bandit 後才進行下一輪。這讓設計保持簡單和可測試。並發可以在之後的 phase 加入。

---

## Component A: Coverage Classifier / Coverage 分類器

### A1: Auto-derived OpcodeBins / 自動推導 OpcodeBins

**EN:** Replace the hand-written `allOpcodeBins` list with automatic derivation from the `Instruction` ADT using `Data.Data`. When a new instruction constructor is added to `Core.Instruction`, its `OpcodeBin` appears automatically — the compiler enforces completeness.

**ZH:** 用 `Data.Data` 反射從 `Instruction` ADT 自動推導 `allOpcodeBins`，取代手寫字串列表。在 `Core.Instruction` 加新 constructor 時，其 `OpcodeBin` 自動出現——編譯器保證完整性。

```haskell
-- Coverage.Types (modified)
-- Uses Data.Data.dataTypeConstrs to enumerate all Instruction constructors
allOpcodeBins :: [CoverageBin]
allOpcodeBins = map (OpcodeBin . T.pack . showConstr) $
  dataTypeConstrs (dataTypeOf (undefined :: Instruction))
```

**Before (current):**
```haskell
allOpcodeBins = map OpcodeBin ["ADD","SUB","ADDI", ...]  -- 手動維護，容易漏
```

**After:**
```haskell
-- 加了 VADD_VV 到 Instruction.hs → OpcodeBin "VADD_VV" 自動出現
-- 不需要改 Coverage.Types
```

### A2: Pluggable PatternDetectors / 可插拔 Pattern 偵測器

**EN:** A `PatternDetector` pairs a `SequencePattern` with a pure detection function over `[Instruction]`. Detectors are registered in `Coverage.Detector` and can be added per-extension without modifying the classifier core. Adding a new extension's patterns = add one new file + one line in the registry.

**ZH:** `PatternDetector` 把 `SequencePattern` 和一個純偵測函式（接受 `[Instruction]`）配對。Detector 在 `Coverage.Detector` 中註冊，可以按 extension 新增，無需修改 classifier 核心。新增 extension 的 patterns = 新增一個檔案 + registry 加一行。

```haskell
-- src/Coverage/Detector.hs
data PatternDetector = PatternDetector
  { pdPattern :: SequencePattern
  , pdDetect  :: [Instruction] -> Bool
  }

-- src/Coverage/Builtin/Detectors.hs
lrscPairDetector :: PatternDetector
lrscPairDetector = PatternDetector LrscPair $ \instrs ->
  any isLR instrs && any isSC instrs

loadUseDetector :: PatternDetector
loadUseDetector = PatternDetector LoadUseDependency $ \instrs ->
  any id [ isLoad a && usesRd b (loadRd a)
         | (a, b) <- zip instrs (tail instrs) ]

-- src/Coverage/Detector.hs
allDetectors :: [PatternDetector]
allDetectors = builtinDetectors  -- 未來: <> rvvDetectors

-- 未來加 RVV:
-- src/Coverage/Builtin/RVV.hs  ← 新檔案
-- allDetectors = builtinDetectors <> rvvDetectors  ← 加一行
```

### A3: Sequence Classifier / 序列分類器

**EN:** `classifySequence` is the single public entry point. It derives opcode bins directly from constructor names, applies all registered pattern detectors with a sliding window, and checks immediate values for value bins.

**ZH:** `classifySequence` 是唯一的公開入口。它直接從 constructor 名稱推導 opcode bins、用滑動視窗套用所有已註冊的 pattern detector、並檢查立即數值判定 value bins。

```haskell
-- src/Coverage/Classify.hs
classifySequence :: [Instruction] -> [CoverageBin]
classifySequence instrs = nub $
  opcodeBins instrs <>
  patternBins instrs <>
  valueBins instrs

-- OpcodeBin: constructor 名稱直接對應
opcodeBins :: [Instruction] -> [CoverageBin]

-- PatternBin: 對每個 detector 跑滑動視窗
patternBins :: [Instruction] -> [CoverageBin]

-- ValueBin: 掃描立即數是否落在各類別
-- Zero=0, One=1, AllOnes=(-1), AlignedAddr=4的倍數...
valueBins :: [Instruction] -> [CoverageBin]
```

**Adding a new extension (e.g., RVV) / 新增 Extension（如 RVV）:**

| 動作 | 現在 | Phase 3 後 |
|------|------|-----------|
| OpcodeBin 要手動補 | ✓ 要 | ✗ 自動 |
| 忘了補 compiler 會警告 | ✗ 不會 | ✓ 不可能漏 |
| Pattern 偵測要改核心 | ✓ 要 | ✗ 只加新檔案 |

---

## Component B: Thompson Sampling Bandit

**EN:** For each `CoverageBin`, maintain a Beta distribution `Beta(α, β)` where α = hits+1, β = misses+1. To choose the next target, sample one value from each distribution and pick the bin with the highest sample. Update after each generation round. Mark infeasible bins (UNSAT from Z3) to exclude them from future sampling.

**ZH:** 對每個 `CoverageBin` 維護 Beta 分佈 `Beta(α, β)`，α = 命中次數+1，β = 未命中次數+1。選擇下一個 target 時，從每個分佈各抽一個值，選最高的 bin。每輪生成後更新。將 infeasible bins（Z3 UNSAT 的 bin）標記為不再抽樣。

```haskell
-- src/Coverage/Bandit.hs
data BanditState = BanditState
  { bsParams      :: Map CoverageBin BetaParams
  , bsInfeasible  :: Set CoverageBin
  }

data BetaParams = BetaParams
  { bpAlpha :: Double   -- hits + 1
  , bpBeta  :: Double   -- misses + 1
  }

initBandit     :: [CoverageBin] -> BanditState          -- Beta(1,1) for all
sampleTarget   :: BanditState -> IO CoverageBin         -- sample → pick max
updateBandit   :: BanditState -> [CoverageBin] -> BanditState  -- update α/β
markInfeasible :: BanditState -> CoverageBin -> BanditState    -- exclude from sampling
```

**Thompson Sampling 範例：**
```
OpcodeBin "MULW"    Beta(1,  15) → sample: 0.06   ← 從未命中
OpcodeBin "FADD_S"  Beta(1,  12) → sample: 0.07
OpcodeBin "ADD"     Beta(55,  2) → sample: 0.93   ← 已高度覆蓋
ValueBin Zero       Beta(1,   5) → sample: 0.17

→ 選 OpcodeBin "ADD"（樣本最高）
→ 但每輪後 ADD 的 α 繼續 +1，Beta 越來越集中在高值，其他 bins 的高 β 讓它們偶爾 spike
→ 幾輪後 MULW/FADD_S 自然被輪到
```

**Beta 分佈採樣：** 使用 `mwc-random` 套件（`System.Random.MWC.Distributions.beta`）。

**為什麼不是 AI/ML：** 沒有神經網路，沒有 gradient descent。純統計採樣，完全可解釋，狀態可序列化為 `Map CoverageBin (Double, Double)`。

---

## Component C: Z3-Guided Generator / Z3 導向生成器

**EN:** Given a target `CoverageBin`, build a `ConstraintSet` and call the existing Z3 solver. If UNSAT (the bin is impossible under current config), fall back to random generation and mark the bin infeasible in the bandit. This activates the existing `SolverDirected` and `Hybrid` modes in `GeneratorMode`.

**ZH:** 給定目標 `CoverageBin`，建立 `ConstraintSet` 並呼叫現有的 Z3 solver。若 UNSAT（當前設定下此 bin 不可能產生），退回 random 生成並在 bandit 中標記此 bin 為 infeasible。這啟用了 `GeneratorMode` 中現有的 `SolverDirected` 和 `Hybrid` 模式。

```haskell
-- src/Generator/Guided.hs

-- 將目標 bin 翻譯成 constraints
binToConstraints :: CoverageBin -> GeneratorConfig -> Maybe ConstraintSet

-- 生成一條針對目標 bin 的指令（UNSAT → Nothing）
guidedInstruction :: CoverageBin -> GeneratorConfig -> IO (Maybe Instruction)

-- 生成完整序列並回傳分類結果
guidedSequence
  :: BanditState
  -> GeneratorConfig
  -> Int                          -- sequence length
  -> IO (InstrSequence, [CoverageBin])
```

**各 Bin 類型的生成策略：**

| Bin 類型 | 策略 |
|---------|------|
| `OpcodeBin "MULW"` | 直接從對應的 `OpcodeCategory` 生成，不需 Z3 |
| `ValueBin Zero` | 生成 ADDI/ANDI/ORI + constraint `imm == 0` → Z3 |
| `ValueBin AlignedAddr` | constraint `imm mod 4 == 0` → Z3 |
| `PatternBin LrscPair` | 生成 LR_D，再生成 SC_D，中間插入 random 指令 |
| `PatternBin LoadUseDependency` | 生成 load rd=r，再生成 ALU rs1=r |
| `OpcodeModeBin "MRET" Machine` | 需要 RVPriv extension；若無則 UNSAT → infeasible |

**UNSAT 處理流程：**
```
guidedInstruction (OpcodeModeBin "MRET" Machine) cfg
  → Z3: UNSAT（RVPriv 未啟用）
  → return Nothing
  → 呼叫方: markInfeasible bandit (OpcodeModeBin "MRET" Machine)
  → 此 bin 不再被 bandit 選中
```

**Hybrid 模式：** `Hybrid p` 表示以機率 `p` 使用 guided generation，以機率 `1-p` 使用 pure random。保持序列多樣性的同時提升覆蓋效率。

---

## Component D: Servant REST API

**EN:** A Servant server exposes the generator, coverage state, and bandit state as a JSON HTTP API. The server runs on a configurable port (default 8080) via Warp. A persistent server state holds the `CoverageAccumulator` and `BanditState` across requests.

**ZH:** Servant server 將 generator、coverage 狀態和 bandit 狀態以 JSON HTTP API 暴露。Server 透過 Warp 在可設定的 port（預設 8080）運行。持久化的 server state 跨請求維護 `CoverageAccumulator` 和 `BanditState`。

### Endpoints / 端點

```
POST /generate
  Request:  { "extensions": ["RV64I","RV64M"],
               "count": 5,
               "mode": "guided" | "random" | "hybrid",
               "length_min": 10, "length_max": 50 }
  Response: { "sequences": [[...], ...],
               "coverage": { "hit": 42, "total": 180, "pct": 23.3 } }

GET /coverage
  Response: { "hit": 143, "total": 180, "pct": 79.4,
               "missing": ["MULW", "PatternBin LrscPair", ...] }

POST /coverage/reset
  Response: 204 No Content

GET /bandit
  Response: { "bins": [
    { "name": "OpcodeBin MULW", "alpha": 1, "beta": 15, "priority": 0.06 },
    { "name": "OpcodeBin ADD",  "alpha": 55, "beta": 2,  "priority": 0.93 },
    ...
  ]}

GET /scenarios
  Response: [{ "name": "lrsc-timer-interrupt",
                "tags": ["Atomic","Interrupt"],
                "extensions": ["RV64A","RVPriv"] }]

POST /scenarios/:name/run
  Response: { "sequence": [...], "coverage_hits": [...] }
```

### Server State / 伺服器狀態

```haskell
-- src/API/Types.hs
data ServerState = ServerState
  { ssAccumulator :: CoverageAccumulator   -- STM TVar, thread-safe
  , ssBandit      :: TVar BanditState      -- STM TVar
  , ssConfig      :: GeneratorConfig
  }
```

### CLI Integration / CLI 整合

```bash
# 新增 server 子命令
cabal run riscv-rig -- server --port 8080

# 現有指令不變
cabal run riscv-rig -- generate --count 5
cabal run riscv-rig -- version
```

---

## File Map / 檔案地圖

| File / 檔案 | Action | Responsibility |
|-------------|--------|----------------|
| `src/Coverage/Classify.hs` | **Create** | `classifySequence` — opcode/pattern/value bin detection |
| `src/Coverage/Detector.hs` | **Create** | `PatternDetector` type + `allDetectors` registry |
| `src/Coverage/Builtin/Detectors.hs` | **Create** | Built-in detectors for all Phase 2 `SequencePattern` values |
| `src/Coverage/Bandit.hs` | **Create** | Thompson Sampling state, `sampleTarget`, `updateBandit` |
| `src/Generator/Guided.hs` | **Create** | `guidedInstruction`, `guidedSequence`, `binToConstraints` |
| `src/API/Types.hs` | **Create** | Request/response JSON types, `ServerState` |
| `src/API/Server.hs` | **Create** | Servant API type + handlers |
| `src/Coverage/Types.hs` | **Modify** | Replace hand-written `allOpcodeBins` with `Data.Data` auto-derive |
| `src/Coverage/Accumulator.hs` | **Modify** | Use `allCoverageBins` (not just `allOpcodeBins`) in snapshot |
| `src/Generator/Random.hs` | **Modify** | Wire `SolverDirected`/`Hybrid` to `Generator.Guided` |
| `app/CLI/Options.hs` | **Modify** | Add `server` subcommand + `--port` option |
| `app/CLI/Runner.hs` | **Modify** | Add `server` runner (start Warp) |
| `riscv-rig.cabal` | **Modify** | Add new modules + new dependencies |
| `test/Test/Coverage/Classify.hs` | **Create** | 8 tests for `classifySequence` |
| `test/Test/Coverage/Bandit.hs` | **Create** | 6 tests for bandit update / sample |
| `test/Test/Generator/Guided.hs` | **Create** | 6 tests for guided generation |
| `test/Test/API/Server.hs` | **Create** | 6 tests for API endpoints (servant-client) |
| `test/Spec.hs` | **Modify** | Add new test modules |

---

## New Dependencies / 新增依賴

```cabal
-- 加入 library build-depends:
, mwc-random     >= 0.15    -- Beta distribution sampling (Bandit)
, servant-server >= 0.20    -- Type-safe HTTP API
, warp           >= 3.3     -- HTTP server runner
, aeson          >= 2.1     -- JSON serialisation

-- 加入 test-suite build-depends:
, servant-client >= 0.20    -- API endpoint tests
, http-client    >= 0.7
```

---

## Key Design Decisions / 關鍵設計決策

**EN:**
1. **Auto-derive OpcodeBins:** Use `Data.Data.dataTypeConstrs` at runtime to enumerate all `Instruction` constructors. New extensions automatically appear in coverage without any manual update.
2. **Pluggable Detectors:** `PatternDetector` decouples detection logic from bin definition. Adding RVV (Phase 6) means one new file, no core changes.
3. **Sequential feedback loop:** Simpler than concurrent; Z3 is the bottleneck anyway. Concurrency can be added in Phase 4/5.
4. **UNSAT → infeasible:** Bins that Z3 cannot satisfy under current config are permanently excluded from bandit sampling, preventing wasted solver calls.
5. **Hybrid mode:** Probability `p` for guided generation preserves diversity; pure guided can get stuck on hard-to-cover bins.
6. **Persistent server state:** `ServerState` holds both `CoverageAccumulator` (STM) and `BanditState` (STM TVar), so coverage persists across multiple `/generate` calls.

**ZH:**
1. **自動推導 OpcodeBins：** 在 runtime 用 `Data.Data.dataTypeConstrs` 枚舉所有 `Instruction` constructor。新 extension 自動出現在 coverage 中，無需任何手動更新。
2. **可插拔 Detector：** `PatternDetector` 將偵測邏輯與 bin 定義解耦。新增 RVV（Phase 6）只需一個新檔案，不動核心。
3. **循序 feedback loop：** 比並發更簡單；Z3 本來就是瓶頸。並發可在 Phase 4/5 加入。
4. **UNSAT → infeasible：** 在當前設定下 Z3 無法滿足的 bins 被永久排除在 bandit 採樣之外，避免浪費 solver 呼叫。
5. **Hybrid 模式：** 機率 `p` 用於 guided generation，保持多樣性；純 guided 可能會卡在難以覆蓋的 bin。
6. **持久化 server state：** `ServerState` 同時持有 `CoverageAccumulator`（STM）和 `BanditState`（STM TVar），coverage 跨多次 `/generate` 呼叫保持不變。

---

## Testing Strategy / 測試策略

**EN:**
- `Test.Coverage.Classify`: verify `LR_D + SC_D → PatternBin LrscPair`; `ADDI imm=0 → ValueBin Zero`; auto-derived opcode bins include all constructors.
- `Test.Coverage.Bandit`: verify rarely-hit bin eventually gets sampled; `updateBandit` increments correct α/β; infeasible bins never sampled.
- `Test.Generator.Guided`: verify `ValueBin Zero` generates instruction with `imm=0`; `OpcodeBin "MULW"` generates MULW; UNSAT bin returns Nothing.
- `Test.API.Server`: verify `/coverage` returns correct JSON structure; `/generate` returns sequences; `/coverage/reset` clears state.

**ZH:**
- `Test.Coverage.Classify`：驗證 `LR_D + SC_D → PatternBin LrscPair`；`ADDI imm=0 → ValueBin Zero`；自動推導的 opcode bins 包含所有 constructor。
- `Test.Coverage.Bandit`：驗證很少命中的 bin 最終被採樣到；`updateBandit` 更新正確的 α/β；infeasible bins 不再被採樣。
- `Test.Generator.Guided`：驗證 `ValueBin Zero` 生成 `imm=0` 的指令；`OpcodeBin "MULW"` 生成 MULW；UNSAT bin 回傳 Nothing。
- `Test.API.Server`：驗證 `/coverage` 回傳正確 JSON 結構；`/generate` 回傳序列；`/coverage/reset` 清空狀態。

---

## Out of Scope for Phase 3 / Phase 3 不包含

- Vue3 frontend dashboard (Phase 5)
- Concurrent / multi-threaded generation (future)
- RVV / Vector extension (Phase 6)
- Authentication / rate-limiting on the API
- Persistent storage (coverage state is in-memory only)
