---
theme: default
title: Pooh-V — SMT-Guided RISC-V Random Instruction Generator
highlighter: shiki
transition: fade
mdc: true
colorSchema: dark
canvasWidth: 1100
fonts:
  sans: Segoe UI, system-ui, sans-serif
  mono: JetBrains Mono, Consolas, monospace
---

<style>
:root {
  --honey: #fbbf24;
  --honey-dark: #d97706;
  --bark: #78350f;
  --forest: #14532d;
  --violet: #6d28d9;
  --blue: #1d4ed8;
}
/* Dark background everywhere — prevents black flash on transition */
html, body, .slidev-container, .slidev-slide { background: #0f172a !important; }

/* Hide Slidev navigation drawer / overview sidebar */
.slidev-nav,
.slidev-overview,
#slidev-nav,
[class*="slidev-nav-"] { display: none !important; }
.slidev-controls { display: flex !important; }

.slidev-layout { background: #0f172a !important; color: #e2e8f0; }
.slidev-layout h1 { color: #fbbf24 !important; }
.slidev-layout h2 { color: #fbbf24 !important; font-size: 1.35em !important; margin-bottom: .25em !important; }
.slidev-layout p, .slidev-layout li { font-size: .82em; }

.badge { display:inline-block; padding:1px 10px; border-radius:999px; font-size:.7em; font-weight:700; margin:2px; }
.b-honey  { background:#d97706; color:#fff; }
.b-forest { background:#14532d; color:#fff; }
.b-bark   { background:#78350f; color:#fbbf24; }
.b-blue   { background:#1d4ed8; color:#fff; }
.b-violet { background:#6d28d9; color:#fff; }
.phase { display:inline-block; background:#78350f; color:#fbbf24; font-weight:800; font-size:.7em; padding:1px 7px; border-radius:4px; margin-right:6px; }
.en { color:#94a3b8; font-style:italic; font-size:.88em; }
.muted { color:#6b7280; }
.card { background:linear-gradient(135deg,rgba(251,191,36,.07),rgba(120,53,15,.12)); border:1px solid rgba(251,191,36,.25); border-radius:10px; padding:.65em .9em; }
.card.green { background:linear-gradient(135deg,rgba(20,83,45,.2),rgba(34,197,94,.06)); border-color:rgba(34,197,94,.3); }
.card.blue  { background:linear-gradient(135deg,rgba(29,78,216,.2),rgba(96,165,250,.06)); border-color:rgba(96,165,250,.3); }
.card.red   { background:linear-gradient(135deg,rgba(220,38,38,.15),rgba(252,165,165,.05)); border-color:rgba(252,165,165,.3); }
.card.violet{ background:linear-gradient(135deg,rgba(109,40,217,.2),rgba(167,139,250,.06)); border-color:rgba(167,139,250,.3); }
.hs-note { background:linear-gradient(90deg,rgba(29,78,216,.15),transparent); border-left:3px solid #fbbf24; padding:.45em .8em; border-radius:0 8px 8px 0; margin:.4em 0; }

/* Dense slides — tighter spacing and smaller text */
.dense h2 { font-size: 1.1em !important; margin-bottom: .15em !important; }
.dense p, .dense li { font-size: .78em !important; line-height: 1.35 !important; }
.dense pre code { font-size: .68em !important; line-height: 1.35 !important; }
.dense table { font-size: .72em !important; }
.dense table td, .dense table th { padding: .2em .45em !important; }
.dense .card { padding: .45em .7em !important; }
.dense .hs-note { padding: .3em .6em !important; margin: .25em 0 !important; }
</style>

<div class="text-center pt-8">
  <div class="text-7xl mb-2">🐻</div>
  <h1 class="text-5xl font-black" style="color:#fbbf24;">Pooh-V</h1>
  <p style="color:#fde68a; font-size:1.1em; margin:.3em 0;">SMT-Guided RISC-V Random Instruction Generator</p>
  <p class="muted" style="font-size:.85em;">用 Haskell 打造的 RISC-V 硬體驗證工具 ／ Hardware verification tooling for RISC-V</p>

  <div class="mt-4">
    <span class="badge b-honey">Haskell</span>
    <span class="badge b-forest">RISC-V RV64GC</span>
    <span class="badge b-bark">SMT / Z3</span>
    <span class="badge b-blue">Property Testing</span>
    <span class="badge b-violet">Servant REST</span>
    <span class="badge b-blue">Vue 3</span>
  </div>

  <div class="flex gap-10 justify-center mt-6 text-sm" style="color:#94a3b8;">
    <span>📦 4 Phases Complete</span>
    <span>🧪 103 Tests Passing</span>
    <span>📐 ~4,000 LoC</span>
  </div>
</div>

---

# 為什麼需要 Pooh-V？ <span class="en">The Problem</span>

<p class="muted">RISC-V 的開放性讓實作百花齊放，但驗證空間是個大問題</p>

<div class="grid grid-cols-3 gap-4 mt-4">
  <div class="card red">
    <strong style="color:#fca5a5;">❌ 手寫測試 Manual Tests</strong>
    <ul class="mt-2 text-sm">
      <li>只測「想到的」case — Only what you think of</li>
      <li>維護成本高 / Hard to maintain</li>
      <li>覆蓋率難量化 / Hard to measure</li>
    </ul>
  </div>
  <div class="card" style="border-color:rgba(251,191,36,.3);">
    <strong style="color:#fbbf24;">⚠️ 純 Random</strong>
    <ul class="mt-2 text-sm">
      <li>廣度還行 / Good breadth</li>
      <li>找不到深層 corner case</li>
      <li>無目標性 / No guidance</li>
    </ul>
  </div>
  <div class="card red">
    <strong style="color:#fca5a5;">❌ Formal Verify</strong>
    <ul class="mt-2 text-sm">
      <li>State space 爆炸 / Explosion</li>
      <li>難應付複雜場景</li>
      <li>Complex scenarios hard</li>
    </ul>
  </div>
</div>

<div class="card green mt-4">
  <strong style="color:#4ade80;">✅ Pooh-V 解法：三者結合 ／ The solution</strong>
  <div class="flex gap-3 mt-2 items-center flex-wrap">
    <div class="card blue px-3 py-1 text-sm">Random Generation<br><span class="muted text-xs">廣度 / Breadth</span></div>
    <span style="color:#fbbf24; font-size:1.3em;">＋</span>
    <div class="card px-3 py-1 text-sm">Constraint Solving<br><span class="muted text-xs">深度 Corner Case</span></div>
    <span style="color:#fbbf24; font-size:1.3em;">＋</span>
    <div class="card violet px-3 py-1 text-sm">Coverage Guidance<br><span class="muted text-xs">可量化 / Measurable</span></div>
    <span style="color:#fbbf24; font-size:1.3em;">＝</span>
    <div class="card green px-3 py-1 text-sm font-bold">Pooh-V 🐻</div>
  </div>
</div>

---
class: dense
---

# 系統架構 <span class="en">System Architecture</span>

<svg viewBox="0 0 900 200" style="width:100%;max-height:190px;" class="mt-2">
  <defs>
    <marker id="arr" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto">
      <polygon points="0 0, 8 3, 0 6" fill="#fbbf24"/>
    </marker>
  </defs>
  <rect x="10"  y="10" width="130" height="48" rx="8" fill="rgba(29,78,216,.35)" stroke="rgba(96,165,250,.5)" stroke-width="1.2"/>
  <text x="75"  y="30" text-anchor="middle" fill="#93c5fd" font-size="11" font-weight="bold">使用者輸入</text>
  <text x="75"  y="47" text-anchor="middle" fill="#64748b" font-size="9">User Input</text>
  <line x1="140" y1="34" x2="165" y2="34" stroke="#fbbf24" stroke-width="1.5" marker-end="url(#arr)"/>
  <rect x="165" y="10" width="145" height="48" rx="8" fill="rgba(120,53,15,.5)" stroke="rgba(251,191,36,.4)" stroke-width="1.2"/>
  <text x="238" y="30" text-anchor="middle" fill="#fde68a" font-size="11" font-weight="bold">Extension Resolver</text>
  <text x="238" y="47" text-anchor="middle" fill="#64748b" font-size="9">依賴 DAG 解析</text>
  <line x1="310" y1="34" x2="335" y2="34" stroke="#fbbf24" stroke-width="1.5" marker-end="url(#arr)"/>
  <rect x="335" y="10" width="160" height="48" rx="8" fill="rgba(109,40,217,.35)" stroke="rgba(167,139,250,.5)" stroke-width="1.2"/>
  <text x="415" y="30" text-anchor="middle" fill="#c4b5fd" font-size="11" font-weight="bold">Constraint Compiler</text>
  <text x="415" y="47" text-anchor="middle" fill="#64748b" font-size="9">SBV → Z3 SMT Query</text>
  <line x1="495" y1="34" x2="520" y2="34" stroke="#fbbf24" stroke-width="1.5" marker-end="url(#arr)"/>
  <rect x="520" y="10" width="130" height="48" rx="8" fill="rgba(120,53,15,.5)" stroke="rgba(251,191,36,.4)" stroke-width="1.2"/>
  <text x="585" y="30" text-anchor="middle" fill="#fde68a" font-size="11" font-weight="bold">Generator</text>
  <text x="585" y="47" text-anchor="middle" fill="#64748b" font-size="9">Solver + Random</text>
  <line x1="650" y1="34" x2="675" y2="34" stroke="#fbbf24" stroke-width="1.5" marker-end="url(#arr)"/>
  <rect x="675" y="10" width="210" height="48" rx="8" fill="rgba(120,53,15,.5)" stroke="rgba(251,191,36,.4)" stroke-width="1.2"/>
  <text x="780" y="30" text-anchor="middle" fill="#fde68a" font-size="11" font-weight="bold">Instruction Sequence</text>
  <text x="780" y="47" text-anchor="middle" fill="#64748b" font-size="9">+ ELF binary wrap</text>
  <line x1="780" y1="58" x2="780" y2="80" stroke="#fbbf24" stroke-width="1.5" marker-end="url(#arr)"/>
  <rect x="630" y="80" width="290" height="50" rx="8" fill="rgba(220,38,38,.25)" stroke="rgba(252,165,165,.4)" stroke-width="1.2"/>
  <text x="775" y="100" text-anchor="middle" fill="#fca5a5" font-size="11" font-weight="bold">CoSim Engine 🔬</text>
  <text x="775" y="118" text-anchor="middle" fill="#64748b" font-size="9">Spike ＋ Sail ＋ Diff Engine</text>
  <line x1="630" y1="105" x2="600" y2="105" stroke="#fbbf24" stroke-width="1.5" marker-end="url(#arr)"/>
  <rect x="440" y="80" width="155" height="50" rx="8" fill="rgba(20,83,45,.3)" stroke="rgba(34,197,94,.4)" stroke-width="1.2"/>
  <text x="518" y="100" text-anchor="middle" fill="#86efac" font-size="11" font-weight="bold">Coverage ✅ PASS</text>
  <text x="518" y="118" text-anchor="middle" fill="#64748b" font-size="9">STM Accumulator</text>
  <line x1="518" y1="130" x2="518" y2="155" stroke="#fbbf24" stroke-width="1.5" marker-end="url(#arr)"/>
  <rect x="260" y="80" width="175" height="50" rx="8" fill="rgba(220,38,38,.2)" stroke="rgba(252,165,165,.35)" stroke-width="1.2"/>
  <text x="347" y="100" text-anchor="middle" fill="#fca5a5" font-size="11" font-weight="bold">Shrinking ❌ FAIL</text>
  <text x="347" y="118" text-anchor="middle" fill="#64748b" font-size="9">Minimal Reproducer</text>
  <rect x="375" y="155" width="285" height="40" rx="8" fill="rgba(109,40,217,.3)" stroke="rgba(167,139,250,.4)" stroke-width="1.2"/>
  <text x="518" y="172" text-anchor="middle" fill="#c4b5fd" font-size="11" font-weight="bold">Coverage Optimizer 🎯 Thompson Sampling Bandit</text>
  <path d="M 375 175 Q 180 195 180 160 Q 180 130 520 34" stroke="rgba(251,191,36,.4)" stroke-width="1.5" fill="none" stroke-dasharray="4 3" marker-end="url(#arr)"/>
  <text x="115" y="195" fill="rgba(251,191,36,.7)" font-size="9">Coverage Feedback Loop</text>
</svg>

<div class="grid grid-cols-3 gap-3 mt-3 text-sm">
  <div class="card"><strong style="color:#fbbf24;">🧱 Pure Core</strong><br><code class="text-xs">Core.* · Constraint.* · Generator.* · Coverage.*</code></div>
  <div class="card"><strong style="color:#fbbf24;">⚡ IO Edge</strong><br><code class="text-xs">CoSim.* · ELF.* · Scenario.*</code></div>
  <div class="card"><strong style="color:#fbbf24;">🌐 API / UI</strong><br><code class="text-xs">API.* Servant REST · Vue 3 Dashboard</code></div>
</div>

---

# 為什麼選 Haskell？ <span class="en">Why Haskell?</span>

<div class="grid grid-cols-3 gap-3 mt-4">
  <div class="card">
    <strong style="color:#fbbf24;">🏗️ ADT = ISA Spec</strong>
    <p class="text-sm mt-1">用 sum type 直接表達指令集。漏掉指令 → compile time 警告，不是 runtime bug。</p>
    <p class="en text-xs">Sum types map perfectly to ISA. Missing case = compile error.</p>
  </div>
  <div class="card">
    <strong style="color:#fbbf24;">🧪 純函數核心</strong>
    <p class="text-sm mt-1">Generator、constraint compiler、coverage accumulator 全是純函數，易測試，結果可重現。</p>
    <p class="en text-xs">Pure core = easy to test, fully reproducible.</p>
  </div>
  <div class="card">
    <strong style="color:#fbbf24;">🔀 STM 無鎖並發</strong>
    <p class="text-sm mt-1">多核 coverage 用 <code>TVar + atomically</code>，不需 mutex，不可能死鎖。</p>
    <p class="en text-xs">Composable transactions, deadlock-free by construction.</p>
  </div>
  <div class="card violet mt-2">
    <strong style="color:#c4b5fd;">🧮 SBV — SMT Binding</strong>
    <p class="text-sm mt-1">直接在 Haskell 寫 Z3 query。Symbolic bitvector 型別安全。</p>
    <p class="en text-xs">Type-safe symbolic bitvectors, Z3 under the hood.</p>
  </div>
  <div class="card blue mt-2">
    <strong style="color:#93c5fd;">🎯 Hedgehog Shrinking</strong>
    <p class="text-sm mt-1">Property-based testing 內建 integrated shrinking，找到 bug 自動縮小序列。</p>
    <p class="en text-xs">Auto-shrinks failing cases to minimal reproducers.</p>
  </div>
  <div class="card mt-2">
    <strong style="color:#fbbf24;">🔗 Servant API</strong>
    <p class="text-sm mt-1">API 型別定義 ＝ 文件 ＝ 實作。handler 型別不對，不讓你 compile。</p>
    <p class="en text-xs">Type-level API spec. Mismatched handler = compile error.</p>
  </div>
</div>

---

# <span class="phase">Phase 1</span> 核心 ISA 模型 <span class="en">Core ISA Model</span>

<div class="grid grid-cols-2 gap-4 mt-3">
<div>

**🏷️ Newtype 型別安全**

```haskell
-- type alias ❌: GHC 看不出差別
type Register   = Word8
type FPRegister = Word8  -- 傳錯了 runtime 才知道

-- newtype ✅: compile time 阻止混用
newtype Register   = Register   { unReg  :: Word8 }
newtype FPRegister = FPRegister { unFReg :: Word8 }
newtype CSRAddr    = CSRAddr    { unCSR  :: Word16 }
newtype Imm12 = Imm12 { unImm12 :: Int16 }
newtype Imm21 = Imm21 { unImm21 :: Int32 }  -- JAL only
```

</div>
<div>

**📋 Instruction Sum Type**

```haskell
data Instruction
  = ADD    Register Register Register
  | ADDI   Register Register Imm12
  | LUI    Register Imm20
  | BEQ    Register Register Imm13
  | JAL    Register Imm21
  | CSRRW  Register CSRAddr Register
  | MUL    Register Register Register
  | MRET
  | SFENCE_VMA Register Register
  deriving (Show, Eq, Ord, Generic)
-- GHC -Wincomplete-patterns 保護你
```

</div>
</div>

<div class="hs-note mt-3">
  <strong style="color:#fbbf24; font-size:.75em; text-transform:uppercase; letter-spacing:.07em;">設計精隨 ／ Key Insight</strong>
  <p class="text-sm mt-1">加入新指令 = 在 ADT 加 constructor。GHC 的 exhaustive pattern match 警告立刻告訴你哪些函數需要更新。<em>The compiler is your spec checker.</em></p>
</div>

---

# <span class="phase">Phase 1</span> Encode / Decode 雙向轉換

<div class="grid grid-cols-2 gap-4 mt-3">
<div>

**encode :: Instruction → Word32**

```haskell
encode :: Instruction -> Word32
encode = \case
  ADD  rd rs1 rs2 -> buildR 0x33 (r rd) 0x0 (r rs1) (r rs2) 0x00
  SUB  rd rs1 rs2 -> buildR 0x33 (r rd) 0x0 (r rs1) (r rs2) 0x20
  MUL  rd rs1 rs2 -> buildR 0x33 (r rd) 0x0 (r rs1) (r rs2) 0x01
  ADDI rd rs1 imm -> buildI 0x13 (r rd) 0x0 (r rs1) (i12 imm)
  BEQ  rs1 rs2 imm -> buildB 0x63 0x0 (r rs1) (r rs2) (i13 imm)
  JAL  rd imm -> buildJ 0x6F (r rd) (i21 imm)
  MRET        -> buildR 0x73 0 0 0 2 0x18  -- spec §3.3.2
```

</div>
<div>

**decode :: Word32 → Either DecodeError Instruction**

```haskell
decode :: Word32 -> Either DecodeError Instruction
decode w = case opcode w of
  0x33 -> decodeR33 w
  0x13 -> decodeI13 w
  0x63 -> decodeBranch w
  0x73 -> decodeSystem w
  op   -> Left (UnknownOpcode op)

data DecodeError
  = UnknownOpcode    Word32
  | UnknownFunct3    Word32 Word32
  | ReservedEncoding Word32
-- Either 強制 caller 處理錯誤
```

</div>
</div>

<div class="card green mt-2 text-sm">
  ✅ <strong>Roundtrip property test：</strong> <code>decode (encode instr) === Right instr</code> — Hedgehog 自動生成 100 個隨機指令，一行程式碼取代數十個 unit test.
</div>

---

# <span class="phase">Phase 1</span> Constraint System — Z3 SMT

<div class="grid grid-cols-2 gap-4 mt-2">
<div>

**ConstraintDef 資料結構**

```haskell
data ConstraintDef = ConstraintDef
  { cname      :: Text
  , ctags      :: [Tag]
  , cpredicate :: SymInstrParams -> SBool
  }

data SymInstrParams = SymInstrParams
  { symRd     :: SWord8
  , symRs1    :: SWord8
  , symImm    :: SInt32
  , symFunct3 :: SWord8 }
```

**常用 Constraint 範例**

```haskell
rdNotZero :: ConstraintDef
rdNotZero = ConstraintDef "rd≠0" [Register]
  (\s -> symRd s ./= 0)

alignedAddr8 :: ConstraintDef
alignedAddr8 = ConstraintDef "8B-align" [Memory]
  (\s -> (symRs1 s + sext (symImm s)) `sMod` 8 .== 0)
```

</div>
<div>

**Combinator eDSL**

```haskell
c1 .&&. c2    -- AND
c1 .||. c2    -- OR
cnot c1       -- NOT
implies c1 c2 -- implication

myConstraints :: ConstraintSet
myConstraints = mempty
  & addConstraint rdNotZero
  & addConstraint alignedAddr8
  & addConstraint (whenExtension RV64A lrscPaired)
```

**Z3 求解**

```haskell
solve :: ConstraintSet -> IO (Maybe InstrParams)
-- Nothing  = UNSAT（constraint 矛盾）
-- Just p   = 一個合法的 assignment

checkFeasibility :: ConstraintSet
                 -> IO FeasibilityResult
```

</div>
</div>

---

# <span class="phase">Phase 1</span> Generator — 兩條路徑 <span class="en">Two-Path Generator</span>

<div class="grid grid-cols-2 gap-4 mt-3">
<div class="card violet">

**🎯 Solver-Directed（深度 / Depth）**

呼叫 Z3 的 optimize mode，在 constraint 解空間的**邊界**尋找 assignment，專門挖 corner case。

```haskell
-- 找邊界點：maximize & minimize 每個 variable
findBoundaryPoints :: SMTQuery -> Int
                   -> IO [PartialAssignment]
```

<span class="en text-xs">Z3 maximize/minimize each field → boundary solutions = corner cases.</span>

</div>
<div class="card blue">

**🌊 Random Path（廣度 / Breadth）**

Hedgehog biased random，在 solver 確認的合法空間內廣度探索，corner value 加權。

```haskell
genCornerCaseImm12 :: Gen Imm12
genCornerCaseImm12 = Gen.frequency
  [ (3, pure (Imm12 0))        -- zero
  , (3, pure (Imm12 2047))     -- max+
  , (3, pure (Imm12 (-2048)))  -- max-
  , (5, genRandom)             -- other
  ]
```

</div>
</div>

<div class="card mt-4 text-sm">
  🌱 <strong style="color:#fbbf24;">Seed &amp; Reproducibility：</strong> 每次 run 都綁定 seed，<code>runWithSeed :: Seed → GeneratorConfig → IO RunResult</code>。發現 bug？記錄 seed，下次必定重現。
</div>

---

# <span class="phase">Phase 1</span> STM Coverage Accumulator

<div class="grid grid-cols-2 gap-4 mt-3">
<div>

```haskell
data CoverageAccumulator = CoverageAccumulator
  { caMap   :: TVar CoverageMap
  , caTotal :: TVar Word64
  }

-- 多個 worker thread 同時更新，不需 mutex
recordCoverage
  :: CoverageAccumulator
  -> [CoverageBin]
  -> STM ()
recordCoverage acc bins =
  modifyTVar (caMap acc) (applyHits bins)
```

```haskell
acc <- newAccumulator
mapM_ (\round -> do
  seqs <- mapM (\_ -> generateSequence cfg) [1..10]
  let bins = concatMap classifySequence seqs
  atomically $ recordCoverage acc bins
  snap <- snapshotCoverage acc
  putStr (renderSummary snap)
  ) [1..roRounds opts]
```

</div>
<div>

**Coverage 六大維度**

| Dimension | Bins | 說明 |
|-----------|------|------|
| Opcode | ~150 | 每個指令跑過？ |
| Value Range | 8× | 極端值 0/max/-1 |
| Seq Pattern | ~50 | LR/SC pair? Load-use? |
| Extension× | N× | A+F+D 同時測？ |
| Privilege | 3× | M/S/U mode |
| Memory Type | 3× | Cache/Uncache/IO |

<div class="hs-note mt-3">
  <strong style="color:#fbbf24; font-size:.75em; text-transform:uppercase;">STM 精隨</strong>
  <p class="text-sm mt-1">STM transaction 可以組合：<code>atomically (a >> b)</code> 保證 a+b 一起成功或回滾。Mutex 做不到。<em>Composable atomicity is a superpower.</em></p>
</div>

</div>
</div>

---

# <span class="phase">Phase 1</span> CoSim Engine <span class="en">Co-Simulation</span>

<p class="muted text-sm">同一個序列跑在多個 RISC-V 實作，比對每一步的 architectural state</p>

<div class="grid grid-cols-2 gap-4 mt-2">
<div>

**Oracle 能力宣告矩陣**

| Oracle | Interrupt | FP Exact | RVWMO | PMA |
|--------|-----------|----------|-------|-----|
| **Spike** ⭐ | ✅ | ✅ | ❌ | ✅ |
| **Sail** ⭐ | ✅ | ✅ | ✅ | ✅ |
| QEMU ⚠️ | ❌ | ❌ | ❌ | ❌ |
| SoftFloat | — | ✅ | — | — |

<div class="card red mt-2 text-sm">
💡 <strong>QEMU 為何幾乎都 ❌：</strong> 用 host FPU、以 translation block 為單位執行（interrupt timing 不準）、host memory model 遮蔽 RVWMO 差異。
</div>

</div>
<div>

```haskell
data MismatchReport = MismatchReport
  { mrSeed    :: Seed        -- 可重現
  , mrPC      :: Word64      -- 哪裡不同
  , mrInstr   :: Instruction -- 哪條指令
  , mrDiffs   :: [StateDiff] -- 具體差異
  , mrContext :: [LogEntry]  -- 前 10 條
  }

data StateDiff
  = GPRDiff Register Word64 Word64
  --         reg      spike   sail
  | FPRDiff FPRegister Double Double
  | CSRDiff CSRAddr Word64 Word64
  | MemDiff Word64 Word8 Word8
```

<div class="hs-note text-sm">
  <strong style="color:#fbbf24; font-size:.75em; text-transform:uppercase;">Shrinking</strong>
  <p>Hedgehog integrated shrinking 自動縮小失敗序列到最小可重現序列。<em>Free shrinking via Hedgehog.</em></p>
</div>

</div>
</div>

---

# <span class="phase">Phase 2</span> 完整 ISA + Scenario DSL

<div class="grid grid-cols-2 gap-4 mt-3">
<div>

**新增 Extensions**

<div class="flex flex-wrap gap-1 my-2">
  <span class="badge b-honey">RV64A — LR/SC/AMO</span>
  <span class="badge b-honey">RV64F — Single FP</span>
  <span class="badge b-honey">RV64D — Double FP</span>
  <span class="badge b-honey">RV64C — Compressed 16-bit</span>
  <span class="badge b-forest">Extension DAG 相依性</span>
</div>

```haskell
-- 自動補齊依賴 (D requires F requires Zicsr)
extensionDeps :: Extension -> [Extension]
extensionDeps RV64D = [RV64F]
extensionDeps RV64F = [Zicsr]
extensionDeps _     = []

resolveExtensions :: Set Extension -> Set Extension
```

</div>
<div>

**LR/SC + Interrupt Scenario**

```haskell
lrscInterruptScenario :: Scenario
lrscInterruptScenario = do
  phase "setup" $ do
    emit (SetPrivilege Machine)
    emit (SetMstatus mIE_enabled)
  phase "lr-acquire" $ do
    useConstraint lrscAqRlComplete
    emit (Instruction LR_D)
    randomN 0 3
  phase "inject" $ do
    emit InjectTimerInterrupt
  phase "trap-handler" $ do
    randomN 5 20
    emit (Instruction MRET)
  phase "sc-verify" $ do
    emit (Instruction SC_D)
    -- reservation 被 interrupt 破壞
    -- SC.D 必須 fail（rd = 1）✅
```

</div>
</div>

---
class: dense
---

# <span class="phase">Phase 3</span> Thompson Sampling Bandit

<p class="muted text-sm">智慧地決定「下一輪生成什麼」，不浪費資源在已覆蓋的地方</p>

<div class="grid grid-cols-2 gap-4 mt-2">
<div>

**Coverage Frontier**

```haskell
-- Frontier = 已 hit 但鄰居未 hit 的 bin
computeFrontier :: CoverageMap -> Set CoverageBin

neighbors :: CoverageBin -> [CoverageBin]
neighbors (ValueBin op Zero) =
  [ValueBin op One, ValueBin op SmallPos]
neighbors (OpcodeBin op) =
  map OpcodeBin (relatedOpcodes op)
```

**Thompson Sampling**

```haskell
data BanditArm = BanditArm
  { armAlpha :: Double  -- successes + 1
  , armBeta  :: Double  -- failures + 1
  }
-- 從 Beta(α, β) sample，選 sample 最大的 arm
-- 自動 exploration vs exploitation 平衡
```

</div>
<div>

<svg viewBox="0 0 320 190" style="width:100%;max-height:190px;">
  <text x="160" y="18" text-anchor="middle" fill="#fbbf24" font-size="12" font-weight="bold">Thompson Sampling</text>
  <text x="160" y="32" text-anchor="middle" fill="#94a3b8" font-size="9">Beta(α, β) 分布 per coverage target</text>
  <path d="M 20 170 C 30 170, 50 55, 80 50 C 110 45, 130 170, 150 170" fill="rgba(34,197,94,.2)" stroke="rgba(34,197,94,.7)" stroke-width="1.5"/>
  <text x="85" y="43" text-anchor="middle" fill="#86efac" font-size="9">已探索 arm</text>
  <text x="85" y="185" text-anchor="middle" fill="#64748b" font-size="8">high confidence</text>
  <path d="M 170 170 C 180 165, 200 130, 230 125 C 260 120, 290 165, 300 170" fill="rgba(251,191,36,.15)" stroke="rgba(251,191,36,.6)" stroke-width="1.5"/>
  <text x="235" y="118" text-anchor="middle" fill="#fde68a" font-size="9">未探索 arm</text>
  <text x="235" y="185" text-anchor="middle" fill="#64748b" font-size="8">uncertain → explore!</text>
  <line x1="10" y1="172" x2="310" y2="172" stroke="#334155" stroke-width="1"/>
</svg>

<div class="hs-note text-sm mt-1">
  <strong style="color:#fbbf24; font-size:.75em; text-transform:uppercase;">為什麼 Thompson Sampling</strong>
  <p>比 ε-greedy 更快收斂，比 UCB1 更適合非平穩分佈（coverage 隨時間改變）。</p>
</div>

</div>
</div>

---

# <span class="phase">Phase 3</span> Servant REST API — 型別安全

<div class="grid grid-cols-2 gap-4 mt-3">
<div>

**API 型別定義**

```haskell
type RigAPI
  =    "coverage"  :> Get  '[JSON] CoverageSnapshot
  :<|> "bandit"    :> Get  '[JSON] BanditSnapshot
  :<|> "run"       :> ReqBody '[JSON] RunRequest
                   :> Post '[JSON] RunResult
  :<|> "scenarios" :> Get  '[JSON] [ScenarioInfo]
  :<|> "events"    :> StreamGet NewlineFraming
                      '[JSON] ServerEvent  -- SSE
```

**Handler 型別自動推導**

```haskell
server :: Server RigAPI
server = getCoverage :<|> getBandit
    :<|> postRun :<|> getScenarios
    :<|> getEvents
-- handler 型別不對 → 不能 compile ✅
```

</div>
<div>

**vs 傳統框架**

| | Servant | Express/Flask |
|---|---------|---------------|
| 型別檢查 | ✅ Compile time | ❌ Runtime |
| 文件同步 | ✅ 自動 | ❌ 手動 |
| 重構安全 | ✅ Type-safe | ❌ 人工確認 |
| OpenAPI | ✅ 自動生成 | ⚠️ 插件 |

<div class="hs-note mt-4">
  <strong style="color:#fbbf24; font-size:.75em; text-transform:uppercase;">精隨</strong>
  <p class="text-sm mt-1">改了 endpoint 的 response type？GHC 立刻告訴你哪個 client 需要更新。<em>The compiler enforces the API contract.</em></p>
</div>

</div>
</div>

---

# <span class="phase">Phase 4</span> Vue3 Dashboard 🍯

<p class="muted text-sm">即時 coverage 視覺化 + SSE 推送 ／ Real-time coverage visualization with Server-Sent Events</p>

<div class="grid grid-cols-2 gap-4 mt-2">
<div>

**Frontend Stack**

<div class="flex flex-col gap-2 text-sm">
  <div class="card py-2 px-3"><strong style="color:#fbbf24;">Vue 3 + TypeScript + Vite</strong> — 前端框架</div>
  <div class="card py-2 px-3"><strong style="color:#fbbf24;">Pinia</strong> — Coverage store, Bandit store</div>
  <div class="card py-2 px-3"><strong style="color:#fbbf24;">Vue Router</strong> — Hash routing (wai-app-static 相容)</div>
  <div class="card py-2 px-3"><strong style="color:#fbbf24;">useSSE composable</strong> — Auto-reconnect EventSource</div>
</div>

**四個頁面**
- 🍯 Coverage — 即時 coverage 統計
- 🌳 Bandit — Thompson Sampling arm 狀態
- ⚙️ Control — 啟動/停止 fuzzing
- 🗺️ Scenarios — Scenario 列表與執行狀態

</div>
<div>

```typescript
// useSSE composable — 自動重連
export function useSSE() {
  const coverage = useCoverageStore()
  const bandit   = useBanditStore()
  let es: EventSource | null = null

  function connect() {
    es = new EventSource('/api/events')
    es.addEventListener('coverage', e =>
      coverage.update(JSON.parse(e.data))
    )
    es.addEventListener('bandit', e =>
      bandit.update(JSON.parse(e.data))
    )
    es.onerror = () => {
      es?.close()
      setTimeout(connect, 2000) // 自動重連
    }
  }
  onMounted(connect)
  onUnmounted(() => es?.close())
}
```

<div class="hs-note text-sm mt-1">
  <p><code>/api/*</code> → Servant；其他 → wai-app-static 服務 Vue dist。<em>Single binary serves both.</em></p>
</div>

</div>
</div>

---
class: dense
---

# 六階段 Roadmap <span class="en">Six-Phase Roadmap</span>

<svg viewBox="0 0 880 75" style="width:100%;max-height:55px;" class="mb-2">
  <rect x="20" y="33" width="840" height="8" rx="4" fill="#1e293b"/>
  <rect x="20" y="33" width="560" height="8" rx="4" fill="#d97706"/>
  <circle cx="90"  cy="37" r="14" fill="#d97706" stroke="#fbbf24" stroke-width="2"/>
  <text x="90"  y="42" text-anchor="middle" fill="#fff" font-size="10" font-weight="bold">1</text>
  <circle cx="230" cy="37" r="14" fill="#d97706" stroke="#fbbf24" stroke-width="2"/>
  <text x="230" y="42" text-anchor="middle" fill="#fff" font-size="10" font-weight="bold">2</text>
  <circle cx="370" cy="37" r="14" fill="#d97706" stroke="#fbbf24" stroke-width="2"/>
  <text x="370" y="42" text-anchor="middle" fill="#fff" font-size="10" font-weight="bold">3</text>
  <circle cx="510" cy="37" r="14" fill="#d97706" stroke="#fbbf24" stroke-width="2"/>
  <text x="510" y="42" text-anchor="middle" fill="#fff" font-size="10" font-weight="bold">4</text>
  <circle cx="650" cy="37" r="14" fill="#1e293b" stroke="#475569" stroke-width="2"/>
  <text x="650" y="42" text-anchor="middle" fill="#9ca3af" font-size="10" font-weight="bold">5</text>
  <circle cx="790" cy="37" r="14" fill="#1e293b" stroke="#475569" stroke-width="2"/>
  <text x="790" y="42" text-anchor="middle" fill="#9ca3af" font-size="10" font-weight="bold">6</text>
  <text x="90"  y="68" text-anchor="middle" fill="#fbbf24" font-size="9">Base ISA</text>
  <text x="230" y="68" text-anchor="middle" fill="#fbbf24" font-size="9">Full ISA+Scenario</text>
  <text x="370" y="68" text-anchor="middle" fill="#fbbf24" font-size="9">Coverage Opt.</text>
  <text x="510" y="68" text-anchor="middle" fill="#fbbf24" font-size="9">Dashboard</text>
  <text x="650" y="68" text-anchor="middle" fill="#64748b" font-size="9">Multi-core</text>
  <text x="790" y="68" text-anchor="middle" fill="#64748b" font-size="9">RVV Vector</text>
</svg>

| Phase | 功能 | Haskell 亮點 | 狀態 |
|-------|------|-------------|------|
| **1** Base | RV64I+M · Encode/Decode · Z3 · Coverage STM · Spike CoSim | Sum types · Newtype · Either · STM · SBV | ✅ Done |
| **2** ISA+ | RV64A/F/D/C · Extension DAG · Scenario DSL · LR/SC interrupt | State monad · Integrated shrinking | ✅ Done |
| **3** Cov. | Thompson Sampling Bandit · Coverage Frontier · Servant REST | Type-safe API · SSE · Beta distribution | ✅ Done |
| **4** UI | Vue3 + Pinia · SSE 即時更新 · wai-app-static | WAI middleware · combineApps | ✅ Done |
| **5** MC | Multi-hart · RVWMO litmus · herd7 · IPI scenario | Par monad · Concurrent IO | 📋 Planned |
| **6** RVV | RV64V Vector · VLEN/ELEN param · Vector coverage | Parameterized types · GADT | 📋 Planned |

---
layout: center
class: text-center
---

<div class="text-5xl mb-4">📚</div>

# Haskell 學習筆記

<p style="color:#a78bfa; font-size:1.1em;">Learning Notes from Pooh-V</p>
<p class="muted text-sm mt-2">從專案中值得學習的八個 Haskell 精隨<br><em>Eight key Haskell concepts illustrated with real Pooh-V code</em></p>

<hr style="border-color:rgba(167,139,250,.3); width:50%; margin:1.5em auto;">

<div class="flex flex-wrap gap-3 justify-center text-sm mt-4" style="color:#94a3b8;">
  <span>① ADT as Spec</span>
  <span>② Newtype Safety</span>
  <span>③ Either Errors</span>
  <span>④ STM Concurrency</span>
  <span>⑤ SBV Symbolic</span>
  <span>⑥ Hedgehog</span>
  <span>⑦ Servant API</span>
  <span>⑧ Syntax Sugar</span>
</div>

---

# ① ADT 作為規格 <span class="en">ADT as Specification</span>

<div class="grid grid-cols-2 gap-4 mt-2">
<div>

**Sum Type = 「其中之一」**

```haskell
-- 一條指令只能是其中一種
data Instruction
  = ADD    Register Register Register
  | ADDI   Register Register Imm12
  | BEQ    Register Register Imm13
  | LUI    Register Imm20
  | MRET
  deriving (Show, Eq, Ord, Generic)

-- GHC -Wincomplete-patterns
-- 漏掉 constructor → compile warning ✅
```

**Product Type = 「同時有」**

```haskell
data RFormat = RFormat
  { rFunct7 :: Word7
  , rRs2    :: Register
  , rRs1    :: Register
  , rFunct3 :: Word3
  , rRd     :: Register
  , rOpcode :: Word7 }
```

</div>
<div>

<div class="card mt-2 text-sm">
  <strong style="color:#fbbf24;">為什麼比 class hierarchy 更好？</strong>
  <ul class="mt-2">
    <li>✅ 加新指令：加一個 constructor（2 行）</li>
    <li>✅ GHC 告訴你哪些 match 需要更新</li>
    <li>✅ Pattern match 在 compile time 窮舉</li>
    <li>✅ <code>deriving (Eq, Ord)</code> 免費得到比較函數</li>
  </ul>
</div>

<div class="hs-note mt-3 text-sm">
  <strong style="color:#fbbf24; font-size:.75em; text-transform:uppercase;">設計精隨</strong>
  <p>Model your domain with types, not strings. ADT 讓「不合法的狀態」在型別層面就不存在。</p>
</div>

</div>
</div>

---

# ② Newtype 型別安全 <span class="en">Type Safety via Newtype</span>

<div class="grid grid-cols-2 gap-4 mt-2">
<div>

```haskell
-- ❌ type alias：GHC 無法區分
type Register   = Word8
type FPRegister = Word8
-- 把 FP register 傳給 GP register 槽 → 不報錯！

-- ✅ newtype：compile time 阻止
newtype Register   = Register   { unReg  :: Word8 }
newtype FPRegister = FPRegister { unFReg :: Word8 }

-- 嘗試混用 → Type error ✅
encodeADD :: Register -> Register -> Register -> Word32
-- encodeADD fp1 x1 x2  ← compile error!
--   Expected: Register
--   Got: FPRegister
```

**Zero-cost abstraction**

```haskell
-- GHC 在機器碼中完全消除 wrapper
-- Smart Constructor 模式
mkRegister :: Word8 -> Maybe Register
mkRegister n
  | n <= 31   = Just (Register n)
  | otherwise = Nothing
```

</div>
<div>

**Immediate 也是獨立型別**

```haskell
newtype Imm12 = Imm12 { unImm12 :: Int16 }
newtype Imm21 = Imm21 { unImm21 :: Int32 }  -- JAL
newtype UImm5 = UImm5 { unUImm5 :: Word8 }  -- shift

-- JAL 需要 Imm21，傳 Imm12 → compile error
JAL rd (imm21 :: Imm21)
```

<div class="card mt-4">
  <strong style="color:#fbbf24;">Newtype 防止的 Bug 類型</strong>
  <ul class="text-sm mt-2">
    <li>Register ≠ FPRegister ≠ CSRAddr</li>
    <li>Imm12 ≠ Imm21 ≠ UImm5</li>
    <li>Seed ≠ Word64（semantic distinction）</li>
    <li>All <strong>zero cost</strong> at runtime</li>
  </ul>
</div>

</div>
</div>

---

# ③ Either 錯誤處理 <span class="en">Error Handling with Either</span>

<div class="grid grid-cols-2 gap-4 mt-2">
<div>

```haskell
-- ❌ Exception 的問題
decode :: Word32 -> Instruction  -- 隱藏失敗

-- ✅ Either：型別簽名明確說明可能失敗
decode :: Word32 -> Either DecodeError Instruction

data DecodeError
  = UnknownOpcode    Word32
  | UnknownFunct3    Word32 Word32
  | ReservedEncoding Word32

-- GHC 強制你處理 Left case
processInstruction :: Word32 -> IO ()
processInstruction w = case decode w of
  Right instr -> execute instr
  Left (UnknownOpcode op) ->
    logWarning ("bad opcode: 0x" <> showHex op "")
  Left (ReservedEncoding raw) ->
    raiseIllegalInstruction raw
```

</div>
<div>

**Monad 組合 — do-notation 短路**

```haskell
-- 任何一步 Left 就短路
processWord :: Word32 -> Either Error Result
processWord w = do
  instr  <- decode w
  params <- extractParams instr
  result <- process params
  return result
```

| 情況 | 用法 |
|------|------|
| 可能失敗，有錯誤信息 | `Either Error a` |
| 可能不存在 | `Maybe a` |
| 真的不該發生 | `error "impossible"` |
| IO 異常 | `IOException` |

<div class="hs-note text-sm mt-2">
  <p><strong>拇指原則：</strong>預期可能發生 → <code>Either</code>。真正的程式錯誤 → <code>error</code>.</p>
</div>

</div>
</div>

---

# ④ STM 並發 <span class="en">Software Transactional Memory</span>

<div class="grid grid-cols-2 gap-4 mt-2">
<div>

```haskell
-- TVar = STM 的可變變數
data CoverageAccumulator = CoverageAccumulator
  { caMap   :: TVar CoverageMap
  , caTotal :: TVar Word64
  }

-- 多個 worker thread 同時更新，不需 lock
worker :: CoverageAccumulator -> IO ()
worker acc = do
  bins <- runTestBatch config
  atomically $
    modifyTVar (caMap acc) (applyHits bins)

-- STM action 可以組合！
atomically $ do
  modifyTVar coverageMap (addBins bins)
  modifyTVar totalCount (+1)
  -- 兩個操作一起成功或一起失敗
```

</div>
<div>

| | Mutex 方式 | STM 方式 |
|---|---|---|
| 死鎖 | ⚠️ 可能 | ✅ 不可能 |
| unlock 忘記 | ⚠️ 可能 | ✅ 不存在 |
| 組合操作 | ❌ 困難 | ✅ `atomically (a >> b)` |
| 條件等待 | ⚠️ condition var | ✅ `retry` |
| 型別保護 | ❌ 無 | ✅ `STM` monad |

<div class="hs-note mt-3 text-sm">
  <p><strong>Composable atomicity is a superpower.</strong> STM transaction 可以像函數一樣組合。Mutex 的組合會導致死鎖風險。</p>
</div>

</div>
</div>

---

# ⑤ SBV Symbolic + ⑥ Hedgehog

<div class="grid grid-cols-2 gap-4 mt-2">
<div>

**⑤ SBV — 兩個世界的對應**

| Concrete | Symbolic |
|----------|----------|
| `Word8` | `SWord8` |
| `Bool` | `SBool` |
| `(==)` | `(.==)` |
| `(/=)` | `(./=)` |
| `(+)` | `(+)` (overloaded) |

```haskell
-- 寫約束，Z3 自動求解
myConstraint :: SymInstrParams -> SBool
myConstraint s =
  symRd s ./= 0           -- rd ≠ x0
  .&& symRs1 s .< 16      -- rs1 < 16
  .&& (symRs1 s + sext (symImm s)) `sMod` 8 .== 0
```

</div>
<div>

**⑥ Hedgehog Property Testing**

```haskell
-- 一行取代幾十個 unit test
prop_roundtrip :: Property
prop_roundtrip = property $ do
  instr <- forAll genInstruction
  decode (encode instr) === Right instr

-- 自動生成 + 自動 shrink
-- 發現失敗自動縮小到最小 case

-- Integrated shrinking：不需另外寫 shrink
genInstruction :: Gen Instruction
genInstruction = Gen.choice
  [ ADD <$> genReg <*> genReg <*> genReg
  , ADDI <$> genReg <*> genReg <*> genImm12
  , MRET -- constant
  ]
```

</div>
</div>

---

# ⑦ Servant API + ⑧ Syntax Sugar

<div class="grid grid-cols-2 gap-4 mt-2">
<div>

**⑦ Servant — Type-level API**

```haskell
-- API 型別 IS the documentation
type MyAPI
  = "users" :> Get '[JSON] [User]
  :<|> "users" :> Capture "id" Int
               :> Get '[JSON] User
  :<|> "users" :> ReqBody '[JSON] NewUser
               :> Post '[JSON] User

-- Handler 型別自動推導
-- 型別不對 → compile error
server :: Server MyAPI
server = getUsers :<|> getUser :<|> createUser
```

</div>
<div>

**⑧ 值得知道的 Syntax Sugar**

```haskell
-- LambdaCase
encode = \case
  ADD rd rs1 rs2 -> ...
  ADDI rd rs1 imm -> ...
-- 等價於 \x -> case x of ...

-- Function application with &
result = mempty
  & addConstraint rdNotZero
  & addConstraint alignedAddr8
-- 等價於 addConstraint alignedAddr8
--          (addConstraint rdNotZero mempty)

-- Record update syntax
newCfg = defaultConfig
  { gcExtensions = parseExtensions exts
  , gcSeed       = seed
  , gcMaxLength  = 50
  }
```

</div>
</div>

---
layout: center
class: text-center
---

<div class="text-6xl mb-4">🐻🍯</div>

# Thank You!

<p style="color:#fde68a; font-size:1.1em; margin:.5em 0;">Pooh-V — Still Hunting for Bugs</p>

<div class="flex gap-8 justify-center mt-6 text-sm" style="color:#94a3b8;">
  <div>
    <div style="color:#fbbf24; font-weight:700;">GitHub</div>
    <div>github.com/lovelessless99/Pooh-V</div>
  </div>
  <div>
    <div style="color:#fbbf24; font-weight:700;">Stack</div>
    <div>Haskell · Z3 · Vue 3 · RISC-V</div>
  </div>
  <div>
    <div style="color:#fbbf24; font-weight:700;">Tests</div>
    <div>103 passing · 4,000 LoC</div>
  </div>
</div>

<div class="mt-8 flex gap-3 justify-center flex-wrap">
  <span class="badge b-honey">Phase 5: Multi-core RVWMO</span>
  <span class="badge b-bark">Phase 6: RVV Vector Extension</span>
</div>
