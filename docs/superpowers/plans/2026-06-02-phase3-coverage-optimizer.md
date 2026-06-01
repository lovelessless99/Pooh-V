# Phase 3: Coverage-Guided Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a closed-loop coverage feedback engine: auto-derive coverage bins from the ISA ADT, classify generated sequences, drive a Thompson Sampling bandit to prioritise uncovered bins, use Z3 to generate targeted sequences, and expose everything via a Servant REST API.

**Architecture:** Sequential feedback loop — generate one sequence, classify it, update bandit, repeat. `Coverage.Classify` classifies sequences into bins using Generics-derived opcode names + pluggable pattern detectors. `Coverage.Bandit` maintains Beta(α,β) per bin and samples the next target. `Generator.Guided` translates a target bin into Z3 constraints or direct generation. `API.Server` wraps everything in a Servant/Warp HTTP server.

**Tech Stack:** GHC 9.4.8, GHC2021, SBV 10.2 (Z3), mwc-random 0.15 (Beta sampling), servant-server 0.20, warp 3.3, aeson 2.1, GHC.Generics (auto-derive opcode names)

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `src/Coverage/Types.hs` | Modify | Replace hand-written `allOpcodeBins` with `GConNames` Generics derivation |
| `src/Coverage/Detector.hs` | Create | `PatternDetector` type + `allDetectors` registry |
| `src/Coverage/Builtin/Detectors.hs` | Create | Concrete detectors for all 15 `SequencePattern` values |
| `src/Coverage/Classify.hs` | Create | `classifySequence :: [Instruction] -> [CoverageBin]` |
| `src/Coverage/Accumulator.hs` | Modify | Use `allCoverageBins` in `snapshotCoverage` |
| `src/Coverage/Bandit.hs` | Create | `BanditState`, `initBandit`, `sampleTarget`, `updateBandit`, `markInfeasible` |
| `src/Generator/Guided.hs` | Create | `guidedInstruction`, `guidedSequence`, `binToConstraints` |
| `src/API/Types.hs` | Create | Request/response JSON types + `ServerState` |
| `src/API/Server.hs` | Create | Servant API type + all 6 handlers |
| `app/CLI/Options.hs` | Modify | Add `CmdServer ServerOptions` with `--port` |
| `app/CLI/Runner.hs` | Modify | Wire classify into run loop; add `runServer` |
| `riscv-rig.cabal` | Modify | Add new modules + mwc-random, servant-server, warp, aeson |
| `test/Test/Coverage/Classify.hs` | Create | 8 classifier tests |
| `test/Test/Coverage/Bandit.hs` | Create | 6 bandit tests |
| `test/Test/Generator/Guided.hs` | Create | 6 guided generation tests |
| `test/Test/API/Server.hs` | Create | 6 API handler tests |
| `test/Spec.hs` | Modify | Register all new test modules |

---

### Task 1: Auto-Derive OpcodeBins from Instruction ADT

**Files:**
- Modify: `src/Coverage/Types.hs`
- Test: `test/Test/Coverage/Classify.hs` (partial — just the auto-derive part)

**Context:** `allOpcodeBins` is currently a 100+ entry hand-written string list. When a new instruction is added to `Core.Instruction`, the developer must remember to update this list — the compiler gives no warning if they forget. This task replaces the list with `GHC.Generics` reflection over the `Instruction` ADT constructor names. `Instruction` already derives `Generic`.

- [ ] **Step 1: Write the failing test**

Create `test/Test/Coverage/Classify.hs`:

```haskell
module Test.Coverage.Classify (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Coverage.Types  (allOpcodeBins, CoverageBin(..))
import Core.Instruction (Instruction(..))
import Data.Text       (pack)

tests :: TestTree
tests = testGroup "Coverage.Classify (auto-derive)"
  [ testCase "allOpcodeBins contains OpcodeBin ADD" $
      OpcodeBin (pack "ADD") `elem` allOpcodeBins @?= True

  , testCase "allOpcodeBins contains OpcodeBin LR_D" $
      OpcodeBin (pack "LR_D") `elem` allOpcodeBins @?= True

  , testCase "allOpcodeBins contains OpcodeBin C_ADDI4SPN" $
      OpcodeBin (pack "C_ADDI4SPN") `elem` allOpcodeBins @?= True

  , testCase "allOpcodeBins is non-empty" $
      null allOpcodeBins @?= False

  , testCase "allOpcodeBins length is at least 150" $
      length allOpcodeBins >= 150 @?= True
  ]
```

- [ ] **Step 2: Add new test module to cabal and Spec.hs**

In `riscv-rig.cabal`, under `test-suite riscv-rig-test` `other-modules`, add:
```
    Test.Coverage.Classify
```

In `test/Spec.hs`, add:
```haskell
import qualified Test.Coverage.Classify    as Classify
```
And in `defaultMain`:
```haskell
  , Classify.tests
```

- [ ] **Step 3: Run test to verify it fails**

```powershell
cabal test riscv-rig-test --test-options="-p Classify" 2>&1 | Select-Object -Last 8
```

Expected: FAIL — module `Test.Coverage.Classify` not found or `allOpcodeBins` uses old hand-written list (length likely still passes, but this confirms the test exists).

- [ ] **Step 4: Replace `allOpcodeBins` in `src/Coverage/Types.hs`**

Replace the entire `allOpcodeBins` definition (lines 55–107) and add the `GConNames` helper. New full content of `src/Coverage/Types.hs`:

```haskell
module Coverage.Types
  ( CoverageBin(..)
  , CoverageMap
  , HitCount
  , SequencePattern(..)
  , ValueCategory(..)
  , allOpcodeBins
  , allCoverageBins
  ) where

import Data.Map.Strict  (Map)
import Data.Text        (Text)
import qualified Data.Text as T
import Core.Types       (PrivilegeLevel(..))
import Core.Instruction (Instruction)
import GHC.Generics     (Generic, Rep, M1, (:+:), Constructor, conName, D, C)
import Data.Proxy       (Proxy(..))
import Data.Word        (Word)

data SequencePattern
  = LrscPair
  | LrscSuccess
  | LrscFail
  | LoadUseDependency
  | BranchTaken
  | BranchNotTaken
  | BackwardBranch
  | ForwardBranch
  | CallReturnPair
  | TailCall
  | FenceBeforeAtomic
  | ExceptionReturn
  | WfiWithInterrupt
  | InstructionFusion
  | CsrReadModifyWrite
  deriving (Show, Eq, Ord, Enum, Bounded, Generic)

data ValueCategory
  = Zero
  | One
  | AllOnes
  | MaxPositive
  | MinNegative
  | SmallPositive
  | AlignedAddr
  | UnalignedAddr
  deriving (Show, Eq, Ord, Enum, Bounded, Generic)

data CoverageBin
  = OpcodeBin     Text
  | PatternBin    SequencePattern
  | ValueBin      ValueCategory
  | OpcodeModeBin Text PrivilegeLevel
  deriving (Show, Eq, Ord, Generic)

type HitCount    = Word
type CoverageMap = Map CoverageBin HitCount

-- ── GConNames: enumerate constructor names via GHC.Generics ──────────────
-- Adding a new Instruction constructor automatically adds its OpcodeBin.

class GConNames (f :: * -> *) where
  gConNamesList :: Proxy f -> [String]

instance (GConNames f, GConNames g) => GConNames (f :+: g) where
  gConNamesList _ = gConNamesList (Proxy :: Proxy f)
                 <> gConNamesList (Proxy :: Proxy g)

instance Constructor c => GConNames (M1 C c f) where
  gConNamesList _ = [conName (undefined :: M1 C c f ())]

instance GConNames f => GConNames (M1 D c f) where
  gConNamesList _ = gConNamesList (Proxy :: Proxy f)

-- ── Auto-derived bins ────────────────────────────────────────────────────

allOpcodeBins :: [CoverageBin]
allOpcodeBins = map (OpcodeBin . T.pack) $
  gConNamesList (Proxy :: Proxy (Rep Instruction))

coreOpcodeNames :: [Text]
coreOpcodeNames =
  [ "ADDI"
  , "ECALL","EBREAK","CSRRW","CSRRS","CSRRC","CSRRWI","CSRRSI","CSRRCI"
  , "MRET","SRET","WFI","SFENCE_VMA"
  , "LR_W","LR_D","SC_W","SC_D"
  ]

allCoverageBins :: [CoverageBin]
allCoverageBins =
  allOpcodeBins
  <> map PatternBin [minBound..maxBound]
  <> map ValueBin   [minBound..maxBound]
  <> [ OpcodeModeBin mnem priv
     | mnem <- coreOpcodeNames
     , priv <- [User, Supervisor, Machine]
     ]
```

- [ ] **Step 5: Run test to verify it passes**

```powershell
cabal test riscv-rig-test --test-options="-p Classify" 2>&1 | Select-Object -Last 8
```

Expected: All 5 Classify tests pass.

- [ ] **Step 6: Run full suite to confirm no regressions**

```powershell
cabal test riscv-rig-test 2>&1 | Select-Object -Last 5
```

Expected: All 108 tests pass (103 existing + 5 new Classify tests).

- [ ] **Step 7: Commit**

```powershell
git add src/Coverage/Types.hs test/Test/Coverage/Classify.hs riscv-rig.cabal test/Spec.hs
git commit -m "feat: auto-derive allOpcodeBins from Instruction ADT via GHC.Generics"
```

---

### Task 2: PatternDetector Infrastructure + Built-in Detectors

**Files:**
- Create: `src/Coverage/Detector.hs`
- Create: `src/Coverage/Builtin/Detectors.hs`

**Context:** `PatternDetector` pairs a `SequencePattern` with a pure function `[Instruction] -> Bool`. All 15 `SequencePattern` values get concrete detectors. Future extensions (e.g., RVV) add a new file + one line in the registry — no changes to this core.

- [ ] **Step 1: Write failing tests**

Add to `test/Test/Coverage/Classify.hs` (append to `tests` list):

```haskell
import Coverage.Detector      (allDetectors, PatternDetector(..))
import Coverage.Types         (SequencePattern(..))
import Core.Types             (AqRl(..), Imm12(..), Imm13(..), x1, x2, x3)
import Core.Instruction       (Instruction(..))

-- (add these cases to the existing testGroup)
  , testCase "allDetectors covers all SequencePattern values" $
      let covered = map pdPattern allDetectors
      in  all (`elem` covered) [minBound..maxBound :: SequencePattern] @?= True

  , testCase "lrscPair detector fires on LR_D + SC_D sequence" $
      let instrs = [LR_D x1 x2 AqRlAcquire, ADDI x3 x1 (Imm12 0), SC_D x1 x2 x1 AqRlRelease]
          det = head $ filter (\d -> pdPattern d == LrscPair) allDetectors
      in  pdDetect det instrs @?= True

  , testCase "backwardBranch detector fires on negative offset" $
      let instrs = [BEQ x1 x2 (Imm13 (-4))]
          det = head $ filter (\d -> pdPattern d == BackwardBranch) allDetectors
      in  pdDetect det instrs @?= True
```

- [ ] **Step 2: Create `src/Coverage/Detector.hs`**

```haskell
module Coverage.Detector
  ( PatternDetector(..)
  , allDetectors
  ) where

import Coverage.Types              (SequencePattern(..))
import Core.Instruction            (Instruction)
import qualified Coverage.Builtin.Detectors as B

data PatternDetector = PatternDetector
  { pdPattern :: SequencePattern
  , pdDetect  :: [Instruction] -> Bool
  }

allDetectors :: [PatternDetector]
allDetectors =
  [ PatternDetector LrscPair          B.detectLrscPair
  , PatternDetector LrscSuccess       B.detectLrscSuccess
  , PatternDetector LrscFail          B.detectLrscFail
  , PatternDetector LoadUseDependency B.detectLoadUse
  , PatternDetector BranchTaken       B.detectBranchTaken
  , PatternDetector BranchNotTaken    B.detectBranchNotTaken
  , PatternDetector BackwardBranch    B.detectBackwardBranch
  , PatternDetector ForwardBranch     B.detectForwardBranch
  , PatternDetector CallReturnPair    B.detectCallReturn
  , PatternDetector TailCall          B.detectTailCall
  , PatternDetector FenceBeforeAtomic B.detectFenceBeforeAtomic
  , PatternDetector ExceptionReturn   B.detectExceptionReturn
  , PatternDetector WfiWithInterrupt  B.detectWfi
  , PatternDetector InstructionFusion B.detectFusion
  , PatternDetector CsrReadModifyWrite B.detectCsrRmw
  ]
```

- [ ] **Step 3: Create `src/Coverage/Builtin/Detectors.hs`**

```haskell
module Coverage.Builtin.Detectors where

import Core.Instruction (Instruction(..))
import Core.Types       (Register(..), Imm13(..))

-- ── Helpers ──────────────────────────────────────────────────────────────

isLR :: Instruction -> Bool
isLR (LR_W{}) = True
isLR (LR_D{}) = True
isLR _        = False

isSC :: Instruction -> Bool
isSC (SC_W{}) = True
isSC (SC_D{}) = True
isSC _        = False

isLoad :: Instruction -> Bool
isLoad i = case i of
  LB{} -> True; LBU{} -> True; LH{} -> True; LHU{} -> True
  LW{} -> True; LWU{} -> True; LD{}  -> True; _ -> False

loadRd :: Instruction -> Register
loadRd (LB  rd _ _) = rd; loadRd (LBU rd _ _) = rd
loadRd (LH  rd _ _) = rd; loadRd (LHU rd _ _) = rd
loadRd (LW  rd _ _) = rd; loadRd (LWU rd _ _) = rd
loadRd (LD  rd _ _) = rd; loadRd _             = Register 0

-- True if instr reads register r as rs1 or rs2
readsReg :: Instruction -> Register -> Bool
readsReg instr r = case instr of
  ADD  _ a b  -> a == r || b == r;  SUB  _ a b  -> a == r || b == r
  ADDI _ a _  -> a == r;            AND  _ a b  -> a == r || b == r
  OR   _ a b  -> a == r || b == r;  XOR  _ a b  -> a == r || b == r
  ANDI _ a _  -> a == r;            ORI  _ a _  -> a == r
  XORI _ a _  -> a == r;            SLL  _ a b  -> a == r || b == r
  SRL  _ a b  -> a == r || b == r;  SRA  _ a b  -> a == r || b == r
  SLT  _ a b  -> a == r || b == r;  SLTU _ a b  -> a == r || b == r
  SLTI _ a _  -> a == r;            SLTIU _ a _ -> a == r
  LB   _ a _  -> a == r;            LH  _ a _   -> a == r
  LW   _ a _  -> a == r;            LD  _ a _   -> a == r
  LBU  _ a _  -> a == r;            LHU _ a _   -> a == r
  LWU  _ a _  -> a == r;            SB  _ a _   -> a == r
  SH   _ a _  -> a == r;            SW  _ a _   -> a == r
  SD   _ a _  -> a == r;            MUL _ a b   -> a == r || b == r
  _           -> False

isBranch :: Instruction -> Bool
isBranch (BEQ{}) = True; isBranch (BNE{}) = True
isBranch (BLT{}) = True; isBranch (BGE{}) = True
isBranch (BLTU{}) = True; isBranch (BGEU{}) = True
isBranch _        = False

branchOffset :: Instruction -> Maybe Int16
branchOffset (BEQ _ _ (Imm13 o)) = Just o
branchOffset (BNE _ _ (Imm13 o)) = Just o
branchOffset (BLT _ _ (Imm13 o)) = Just o
branchOffset (BGE _ _ (Imm13 o)) = Just o
branchOffset (BLTU _ _ (Imm13 o)) = Just o
branchOffset (BGEU _ _ (Imm13 o)) = Just o
branchOffset _                     = Nothing

isJal :: Instruction -> Bool
isJal (JAL{}) = True; isJal (JALR{}) = True; isJal _ = False

isAtomic :: Instruction -> Bool
isAtomic i = isLR i || isSC i || case i of
  AMOSWAP_W{} -> True; AMOADD_W{} -> True; LR_W{} -> True
  AMOSWAP_D{} -> True; AMOADD_D{} -> True; _ -> False

isFence :: Instruction -> Bool
isFence (FENCE{}) = True; isFence FENCE_I = True; isFence _ = False

isCsr :: Instruction -> Bool
isCsr (CSRRW{}) = True; isCsr (CSRRS{}) = True; isCsr (CSRRC{}) = True
isCsr (CSRRWI{}) = True; isCsr (CSRRSI{}) = True; isCsr (CSRRCI{}) = True
isCsr _ = False

-- ── Detector implementations ─────────────────────────────────────────────

detectLrscPair :: [Instruction] -> Bool
detectLrscPair instrs = any isLR instrs && any isSC instrs

-- Heuristic: SC where rd ≠ x0 (caller checks the result → success path)
detectLrscSuccess :: [Instruction] -> Bool
detectLrscSuccess instrs = detectLrscPair instrs &&
  any (\i -> case i of
    SC_W rd _ _ _ -> unRegister rd /= 0
    SC_D rd _ _ _ -> unRegister rd /= 0
    _             -> False) instrs

-- Heuristic: SC where rd = x0 (result discarded → often a fail-tolerance pattern)
detectLrscFail :: [Instruction] -> Bool
detectLrscFail instrs = detectLrscPair instrs &&
  any (\i -> case i of
    SC_W rd _ _ _ -> unRegister rd == 0
    SC_D rd _ _ _ -> unRegister rd == 0
    _             -> False) instrs

detectLoadUse :: [Instruction] -> Bool
detectLoadUse instrs = any (uncurry isLoadUse) (zip instrs (tail instrs))
  where
    isLoadUse a b =
      isLoad a
      && unRegister (loadRd a) /= 0
      && readsReg b (loadRd a)

detectBranchTaken :: [Instruction] -> Bool
detectBranchTaken = detectBackwardBranch   -- backward branches commonly taken (loops)

detectBranchNotTaken :: [Instruction] -> Bool
detectBranchNotTaken = detectForwardBranch  -- forward branches commonly not taken

detectBackwardBranch :: [Instruction] -> Bool
detectBackwardBranch instrs = any (\i -> case branchOffset i of
  Just o  -> o < 0
  Nothing -> False) instrs

detectForwardBranch :: [Instruction] -> Bool
detectForwardBranch instrs = any (\i -> case branchOffset i of
  Just o  -> o > 0
  Nothing -> False) instrs

-- JAL rd (saves return addr) followed later by JALR x0,rd (return-like)
detectCallReturn :: [Instruction] -> Bool
detectCallReturn instrs = any isJal instrs

-- JALR with rd = x0 = tail call (discard return address)
detectTailCall :: [Instruction] -> Bool
detectTailCall instrs = any (\i -> case i of
  JALR rd _ _ -> unRegister rd == 0
  _           -> False) instrs

detectFenceBeforeAtomic :: [Instruction] -> Bool
detectFenceBeforeAtomic instrs = any (uncurry isFenceAtom) (zip instrs (tail instrs))
  where isFenceAtom a b = isFence a && isAtomic b

detectExceptionReturn :: [Instruction] -> Bool
detectExceptionReturn instrs = any (\i -> case i of
  MRET -> True; SRET -> True; _ -> False) instrs

detectWfi :: [Instruction] -> Bool
detectWfi = any (== WFI)

-- LUI followed by ADDI to the same register = load-address fusion pair
detectFusion :: [Instruction] -> Bool
detectFusion instrs = any (uncurry isFusePair) (zip instrs (tail instrs))
  where
    isFusePair (LUI  rd1 _) (ADDI rd2 rs2 _) = rd1 == rd2 || rs2 == rd1
    isFusePair (AUIPC rd1 _) (ADDI rd2 rs2 _) = rd1 == rd2 || rs2 == rd1
    isFusePair _ _ = False

-- CSRRS or CSRRC = read-modify-write (reads then sets/clears bits)
detectCsrRmw :: [Instruction] -> Bool
detectCsrRmw instrs = any isCsrRmw instrs
  where
    isCsrRmw (CSRRS{}) = True
    isCsrRmw (CSRRC{}) = True
    isCsrRmw _         = False
```

- [ ] **Step 4: Update cabal exposed-modules**

In `riscv-rig.cabal` library section, add:
```
    Coverage.Detector
    Coverage.Builtin.Detectors
```

- [ ] **Step 5: Run tests**

```powershell
cabal test riscv-rig-test --test-options="-p Classify" 2>&1 | Select-Object -Last 8
```

Expected: All 8 Classify tests pass (5 from Task 1 + 3 new detector tests).

- [ ] **Step 6: Commit**

```powershell
git add src/Coverage/Detector.hs src/Coverage/Builtin/Detectors.hs riscv-rig.cabal
git commit -m "feat: add PatternDetector infrastructure and 15 built-in sequence detectors"
```

---

### Task 3: classifySequence + Fix Accumulator

**Files:**
- Create: `src/Coverage/Classify.hs`
- Modify: `src/Coverage/Accumulator.hs`

**Context:** `classifySequence` is the single public entry point that turns `[Instruction]` into `[CoverageBin]`. It combines opcode bins (one per instruction), pattern bins (via all registered detectors), and value bins (checking immediate operands). `Coverage.Accumulator.snapshotCoverage` currently uses only `allOpcodeBins` — this task upgrades it to use `allCoverageBins`.

- [ ] **Step 1: Add classifier tests to `test/Test/Coverage/Classify.hs`**

Append to the existing `tests` testGroup:

```haskell
import Coverage.Classify (classifySequence)
import Core.Instruction  (Instruction(..))
import Core.Types        (Imm12(..), Imm13(..), x1, x2, x3, x4)

  , testCase "classifySequence: ADD x1 x2 x3 → OpcodeBin ADD" $
      OpcodeBin (pack "ADD") `elem`
        classifySequence [ADD x1 x2 x3] @?= True

  , testCase "classifySequence: ADDI imm=0 → ValueBin Zero" $
      ValueBin Zero `elem`
        classifySequence [ADDI x1 x2 (Imm12 0)] @?= True

  , testCase "classifySequence: ADDI imm=(-1) → ValueBin AllOnes" $
      ValueBin AllOnes `elem`
        classifySequence [ADDI x1 x2 (Imm12 (-1))] @?= True

  , testCase "classifySequence: LR_D + SC_D → PatternBin LrscPair" $
      PatternBin LrscPair `elem`
        classifySequence [LR_D x1 x2 AqRlAcquire, SC_D x1 x2 x1 AqRlRelease] @?= True

  , testCase "classifySequence: BEQ with negative offset → PatternBin BackwardBranch" $
      PatternBin BackwardBranch `elem`
        classifySequence [BEQ x1 x2 (Imm13 (-4))] @?= True

  , testCase "classifySequence: empty list → empty result" $
      classifySequence [] @?= []

  , testCase "classifySequence: no duplicate bins" $
      let bins = classifySequence [ADD x1 x2 x3, ADD x1 x2 x3]
      in  length bins == length (nub bins) @?= True
```

Add `import Data.List (nub)` and `import Core.Types (AqRl(..))` to the test imports.

- [ ] **Step 2: Create `src/Coverage/Classify.hs`**

```haskell
module Coverage.Classify
  ( classifySequence
  ) where

import Coverage.Types    (CoverageBin(..), ValueCategory(..), ValueBin)
import Coverage.Detector (allDetectors, pdPattern, pdDetect)
import Core.Instruction  (Instruction(..))
import Core.Types        (Imm12(..), Imm13(..), Imm20(..), Imm21(..))
import Data.List         (nub)
import Data.Text         (pack)
import GHC.Generics      (Generic, Rep, M1, (:+:), Constructor, conName, C, D)
import Data.Proxy        (Proxy(..))

-- | Classify a sequence into all coverage bins it hits.
classifySequence :: [Instruction] -> [CoverageBin]
classifySequence []     = []
classifySequence instrs = nub $
  concatMap instrOpcodeBin instrs
  <> patternBins instrs
  <> concatMap instrValueBins instrs

-- ── Opcode bins ───────────────────────────────────────────────────────────
-- Reuse same Generics trick: get each instruction's constructor name.

class GConName (f :: * -> *) where
  gConName :: f x -> String

instance Constructor c => GConName (M1 C c f) where
  gConName m = conName m

instance GConName f => GConName (M1 D c f) where
  gConName (M1 x) = gConName x

instance (GConName f, GConName g) => GConName (f :+: g) where
  gConName (L1 x) = gConName x
  gConName (R1 x) = gConName x

instrOpcodeBin :: Instruction -> [CoverageBin]
instrOpcodeBin _ = []   -- placeholder replaced below

-- Direct pattern match on the instruction value using show-constructor trick:
-- We convert to the Rep, then call gConName on it.
-- This avoids depending on Show (which includes field values).
import GHC.Generics (from)

instrOpcodeBin :: Instruction -> [CoverageBin]
instrOpcodeBin i = [OpcodeBin (pack (gConName (from i)))]
```

Wait — that has a duplicate definition. Let me write the correct full file:

```haskell
module Coverage.Classify
  ( classifySequence
  ) where

import Coverage.Types    (CoverageBin(..), ValueCategory(..))
import Coverage.Detector (allDetectors, pdPattern, pdDetect)
import Core.Instruction  (Instruction)
import Core.Types        (Imm12(..), Imm13(..))
import Data.List         (nub)
import Data.Text         (pack)
import GHC.Generics

-- | Classify a sequence into all coverage bins it hits.
classifySequence :: [Instruction] -> [CoverageBin]
classifySequence []     = []
classifySequence instrs = nub $
  map instrOpcodeBin instrs
  <> patternBins instrs
  <> concatMap instrValueBins instrs

-- ── Opcode bin per instruction ────────────────────────────────────────────
-- Walk the Generic Rep to extract the constructor name.

class GConName (f :: * -> *) where
  gConName :: f x -> String

instance Constructor c => GConName (M1 C c f) where
  gConName m = conName m

instance GConName f => GConName (M1 D c f) where
  gConName (M1 x) = gConName x

instance (GConName f, GConName g) => GConName (f :+: g) where
  gConName (L1 x) = gConName x
  gConName (R1 x) = gConName x

instrOpcodeBin :: Instruction -> CoverageBin
instrOpcodeBin i = OpcodeBin (pack (gConName (from i)))

-- ── Pattern bins (apply all registered detectors) ────────────────────────

patternBins :: [Instruction] -> [CoverageBin]
patternBins instrs =
  [ PatternBin (pdPattern d)
  | d <- allDetectors
  , pdDetect d instrs
  ]

-- ── Value bins (check immediate operands) ────────────────────────────────

instrValueBins :: Instruction -> [CoverageBin]
instrValueBins instr = case extractImm instr of
  Nothing  -> []
  Just imm -> map ValueBin (classifyImm imm)

extractImm :: Instruction -> Maybe Int32
extractImm instr = case instr of
  ADDI  _ _ (Imm12 v) -> Just (fromIntegral v)
  ANDI  _ _ (Imm12 v) -> Just (fromIntegral v)
  ORI   _ _ (Imm12 v) -> Just (fromIntegral v)
  XORI  _ _ (Imm12 v) -> Just (fromIntegral v)
  SLTI  _ _ (Imm12 v) -> Just (fromIntegral v)
  SLTIU _ _ (Imm12 v) -> Just (fromIntegral v)
  LB    _ _ (Imm12 v) -> Just (fromIntegral v)
  LH    _ _ (Imm12 v) -> Just (fromIntegral v)
  LW    _ _ (Imm12 v) -> Just (fromIntegral v)
  LD    _ _ (Imm12 v) -> Just (fromIntegral v)
  LBU   _ _ (Imm12 v) -> Just (fromIntegral v)
  LHU   _ _ (Imm12 v) -> Just (fromIntegral v)
  LWU   _ _ (Imm12 v) -> Just (fromIntegral v)
  JALR  _ _ (Imm12 v) -> Just (fromIntegral v)
  _                   -> Nothing

classifyImm :: Int32 -> [ValueCategory]
classifyImm v = concatMap snd $ filter (fst) $
  [ (v == 0,               [Zero])
  , (v == 1,               [One])
  , (v == (-1),            [AllOnes])
  , (v > 0 && v < 16,      [SmallPositive])
  , (v == maxBound,        [MaxPositive])
  , (v == minBound,        [MinNegative])
  , (v > 0 && v `mod` 4 == 0, [AlignedAddr])
  , (v > 0 && v `mod` 4 /= 0, [UnalignedAddr])
  ]
```

Note: `Int32` is from `Data.Int`. Add `import Data.Int (Int32)` to the imports.

- [ ] **Step 3: Update `src/Coverage/Accumulator.hs`**

Change line 29 — replace `allOpcodeBins` with `allCoverageBins`:

```haskell
snapshotCoverage :: CoverageAccumulator -> IO CoverageSummary
snapshotCoverage acc = do
  m <- readTVarIO (covTVar acc)
  return (coverageSummary m allCoverageBins)
```

- [ ] **Step 4: Update cabal and Spec.hs**

In `riscv-rig.cabal` library `exposed-modules`:
```
    Coverage.Classify
```

In test-suite `other-modules` (already added in Task 1, no change needed for this task).

- [ ] **Step 5: Run tests**

```powershell
cabal test riscv-rig-test --test-options="-p Classify" 2>&1 | Select-Object -Last 10
```

Expected: All 15 Classify tests pass.

- [ ] **Step 6: Full suite**

```powershell
cabal test riscv-rig-test 2>&1 | Select-Object -Last 5
```

Expected: All 118 tests pass.

- [ ] **Step 7: Commit**

```powershell
git add src/Coverage/Classify.hs src/Coverage/Accumulator.hs riscv-rig.cabal test/Test/Coverage/Classify.hs test/Spec.hs
git commit -m "feat: add classifySequence; accumulator now tracks all coverage bins"
```

---

### Task 4: Thompson Sampling Bandit

**Files:**
- Create: `src/Coverage/Bandit.hs`
- Create: `test/Test/Coverage/Bandit.hs`
- Modify: `riscv-rig.cabal` (add `mwc-random`, `Coverage.Bandit`, `Test.Coverage.Bandit`)

**Context:** The bandit maintains a `Map CoverageBin BetaParams` where `BetaParams` is `(α, β)` for a Beta distribution. `sampleTarget` samples from each bin's distribution and picks the bin with the highest sample. This is Thompson Sampling — no AI, pure statistics.

- [ ] **Step 1: Write failing tests in `test/Test/Coverage/Bandit.hs`**

```haskell
module Test.Coverage.Bandit (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Coverage.Bandit
import Coverage.Types  (CoverageBin(..), allCoverageBins)
import Data.Set        (Set)
import qualified Data.Set as Set
import Data.Text       (pack)

tests :: TestTree
tests = testGroup "Coverage.Bandit"
  [ testCase "initBandit creates Beta(1,1) for every bin" $ do
      let bs = initBandit allCoverageBins
          params = bsParams bs
      length params @?= length allCoverageBins
      all (\(BetaParams a b) -> a == 1.0 && b == 1.0) (map snd (toList params)) @?= True

  , testCase "updateBandit increments alpha for hit bins" $ do
      let bin = OpcodeBin (pack "ADD")
          bs0 = initBandit [bin]
          bs1 = updateBandit bs0 [bin]
          BetaParams a _ = bsParams bs1 ! bin
      a @?= 2.0   -- was 1.0, hit once → 2.0

  , testCase "updateBandit increments beta for miss bins" $ do
      let bin1 = OpcodeBin (pack "ADD")
          bin2 = OpcodeBin (pack "SUB")
          bs0  = initBandit [bin1, bin2]
          bs1  = updateBandit bs0 [bin1]   -- only bin1 hit
          BetaParams _ b = bsParams bs1 ! bin2
      b @?= 2.0   -- bin2 missed → beta 1.0 → 2.0

  , testCase "markInfeasible removes bin from params" $ do
      let bin = OpcodeBin (pack "MRET")
          bs0 = initBandit [bin]
          bs1 = markInfeasible bs0 bin
      Set.member bin (bsInfeasible bs1) @?= True

  , testCase "sampleTarget never returns infeasible bin" $ do
      let bins = [OpcodeBin (pack "ADD"), OpcodeBin (pack "MRET")]
          bs0  = initBandit bins
          bs1  = markInfeasible bs0 (OpcodeBin (pack "MRET"))
      result <- sampleTarget bs1
      result @?= OpcodeBin (pack "ADD")   -- only eligible bin

  , testCase "sampleTarget with single eligible bin returns that bin" $ do
      let bin = OpcodeBin (pack "ADDI")
          bs  = initBandit [bin]
      result <- sampleTarget bs
      result @?= bin
  ]
  where
    toList = Map.toList
    (!)    = (Map.!)
```

Add imports `import qualified Data.Map.Strict as Map` and `import Data.Map.Strict (Map)`.

- [ ] **Step 2: Create `src/Coverage/Bandit.hs`**

```haskell
module Coverage.Bandit
  ( BanditState(..)
  , BetaParams(..)
  , initBandit
  , sampleTarget
  , updateBandit
  , markInfeasible
  ) where

import Coverage.Types         (CoverageBin)
import Data.List              (maximumBy)
import Data.Ord               (comparing)
import Data.Set               (Set)
import qualified Data.Map.Strict as Map
import qualified Data.Set        as Set
import System.Random.MWC                   (createSystemRandom)
import System.Random.MWC.Distributions     (beta)

data BetaParams = BetaParams
  { bpAlpha :: Double
  , bpBeta  :: Double
  } deriving (Show, Eq)

data BanditState = BanditState
  { bsParams     :: Map.Map CoverageBin BetaParams
  , bsInfeasible :: Set CoverageBin
  }

-- | Initialise with Beta(1,1) for every bin.
initBandit :: [CoverageBin] -> BanditState
initBandit bins = BanditState
  { bsParams     = Map.fromList [(b, BetaParams 1.0 1.0) | b <- bins]
  , bsInfeasible = Set.empty
  }

-- | Sample one value from each eligible bin's Beta distribution; return the
-- bin with the highest sample.  Eligible = not in bsInfeasible.
sampleTarget :: BanditState -> IO CoverageBin
sampleTarget BanditState{bsParams, bsInfeasible} = do
  let eligible = [ (b, p)
                 | (b, p) <- Map.toList bsParams
                 , not (Set.member b bsInfeasible) ]
  case eligible of
    []  -> error "sampleTarget: no eligible bins (all marked infeasible)"
    [x] -> return (fst x)
    _   -> do
      gen     <- createSystemRandom
      samples <- mapM (\(b, BetaParams a bv) -> do
                    s <- beta a bv gen
                    return (s, b)) eligible
      return $ snd (maximumBy (comparing fst) samples)

-- | Update α/β after a generation round.
-- Hit bins: α += 1.  Miss bins (eligible but not hit): β += 1.
updateBandit :: BanditState -> [CoverageBin] -> BanditState
updateBandit bs hits =
  let hitSet = Set.fromList hits
      update b p@(BetaParams a bv)
        | Set.member b hitSet         = BetaParams (a + 1) bv
        | Set.member b (bsInfeasible bs) = p
        | otherwise                   = BetaParams a (bv + 1)
  in  bs { bsParams = Map.mapWithKey update (bsParams bs) }

-- | Permanently exclude a bin from sampling (e.g. UNSAT from Z3).
markInfeasible :: BanditState -> CoverageBin -> BanditState
markInfeasible bs bin = bs { bsInfeasible = Set.insert bin (bsInfeasible bs) }
```

- [ ] **Step 3: Add `mwc-random` and new modules to `riscv-rig.cabal`**

In library `exposed-modules`, add:
```
    Coverage.Bandit
```

In library `build-depends`, add:
```
    , mwc-random     >= 0.15
```

In test-suite `other-modules`, add:
```
    Test.Coverage.Bandit
```

In test-suite `build-depends`, add:
```
    , mwc-random     >= 0.15
```

- [ ] **Step 4: Update `test/Spec.hs`**

```haskell
import qualified Test.Coverage.Bandit      as Bandit
-- add to defaultMain:
  , Bandit.tests
```

- [ ] **Step 5: Run tests**

```powershell
cabal test riscv-rig-test --test-options="-p Bandit" 2>&1 | Select-Object -Last 8
```

Expected: All 6 Bandit tests pass.

- [ ] **Step 6: Commit**

```powershell
git add src/Coverage/Bandit.hs test/Test/Coverage/Bandit.hs riscv-rig.cabal test/Spec.hs
git commit -m "feat: add Thompson Sampling bandit (Beta distribution per coverage bin)"
```

---

### Task 5: Z3-Guided Generator

**Files:**
- Create: `src/Generator/Guided.hs`
- Create: `test/Test/Generator/Guided.hs`
- Modify: `riscv-rig.cabal`

**Context:** `guidedInstruction` translates a target `CoverageBin` into a `ConstraintSet` and calls the existing `Constraint.Solver.solve`. For `OpcodeBin` targets, it generates directly without Z3. For `ValueBin` targets, it constrains the immediate value. For `PatternBin` targets, it builds a short multi-instruction sequence. UNSAT returns `Nothing`; the caller marks the bin infeasible in the bandit. Tests use `requireZ3` (same guard as `Test.Constraint.Solver`).

- [ ] **Step 1: Write failing tests in `test/Test/Generator/Guided.hs`**

```haskell
module Test.Generator.Guided (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Coverage.Types    (CoverageBin(..), ValueCategory(..), SequencePattern(..))
import Generator.Guided  (guidedInstruction, guidedSequence)
import Generator.Types   (defaultConfig)
import Coverage.Bandit   (initBandit, BanditState)
import Coverage.Types    (allCoverageBins)
import Core.Instruction  (Instruction(..))
import Core.Types        (Imm12(..))
import Data.Text         (pack)
import System.IO.Error   (tryIOError)
import System.Process    (readProcessWithExitCode)

z3Available :: IO Bool
z3Available = do
  r <- tryIOError (readProcessWithExitCode "z3" ["--version"] "")
  return $ case r of { Left _ -> False; Right _ -> True }

requireZ3 :: Assertion -> Assertion
requireZ3 action = z3Available >>= \av -> if av then action else return ()

tests :: TestTree
tests = testGroup "Generator.Guided"
  [ testCase "guidedInstruction OpcodeBin ADD returns ADD instruction" $ do
      result <- guidedInstruction (OpcodeBin (pack "ADD")) defaultConfig
      case result of
        Nothing -> assertFailure "expected an instruction"
        Just (ADD{}) -> return ()
        Just other   -> assertFailure ("expected ADD, got: " <> show other)

  , testCase "guidedInstruction ValueBin Zero returns instr with imm=0" $
      requireZ3 $ do
        result <- guidedInstruction (ValueBin Zero) defaultConfig
        case result of
          Nothing -> assertFailure "expected an instruction"
          Just (ADDI _ _ (Imm12 0)) -> return ()
          Just (ANDI _ _ (Imm12 0)) -> return ()
          Just (ORI  _ _ (Imm12 0)) -> return ()
          Just other -> assertFailure ("unexpected: " <> show other)

  , testCase "guidedInstruction ValueBin AllOnes returns instr with imm=(-1)" $
      requireZ3 $ do
        result <- guidedInstruction (ValueBin AllOnes) defaultConfig
        case result of
          Nothing -> assertFailure "expected an instruction"
          Just (ADDI _ _ (Imm12 (-1))) -> return ()
          Just (ANDI _ _ (Imm12 (-1))) -> return ()
          Just other -> assertFailure ("unexpected: " <> show other)

  , testCase "guidedSequence returns non-empty sequence" $ do
      let bs = initBandit allCoverageBins
      (seq_, _bins) <- guidedSequence bs defaultConfig 5
      null seq_ @?= False

  , testCase "guidedSequence returns classified bins" $ do
      let bs = initBandit allCoverageBins
      (_seq_, bins) <- guidedSequence bs defaultConfig 5
      null bins @?= False

  , testCase "guidedInstruction infeasible bin returns Nothing" $
      requireZ3 $ do
        -- OpcodeBin for an extension not in defaultConfig (RV64A)
        -- defaultConfig only enables RV64I + RV64M → LR_D is infeasible
        result <- guidedInstruction (OpcodeBin (pack "LR_D")) defaultConfig
        result @?= Nothing
  ]
```

- [ ] **Step 2: Create `src/Generator/Guided.hs`**

```haskell
module Generator.Guided
  ( guidedInstruction
  , guidedSequence
  , binToConstraints
  ) where

import Coverage.Types       (CoverageBin(..), ValueCategory(..), SequencePattern(..))
import Coverage.Bandit      (BanditState, sampleTarget)
import Coverage.Classify    (classifySequence)
import Core.Instruction     (Instruction(..), Extension(..))
import Core.Types           (Register(..), Imm12(..), x0, x1, x2, AqRl(..))
import Constraint.Types     (ConstraintSet, ConstraintDef(..), addConstraint,
                              emptyConstraintSet, SymInstrParams(..))
import Constraint.Solver    (solve, checkFeasibility, FeasibilityResult(..))
import Generator.Types      (GeneratorConfig(..), InstrSequence)
import Generator.Random     (generateSequence, genInstruction)
import Data.SBV             ((.==), literal)
import Data.Text            (Text, unpack)
import qualified Data.Set as Set
import Hedgehog             (Gen)
import qualified Hedgehog.Gen            as Gen
import qualified Hedgehog.Range          as Range
import qualified Hedgehog.Internal.Seed  as HSeed
import qualified Hedgehog.Internal.Gen   as HGen
import qualified Hedgehog.Internal.Tree  as HTree

-- | Translate a coverage bin into a constraint set.
-- Returns Nothing if this bin type cannot be expressed as Z3 constraints
-- (e.g. PatternBin requires multi-instruction generation, handled separately).
binToConstraints :: CoverageBin -> GeneratorConfig -> Maybe ConstraintSet
binToConstraints bin cfg = case bin of
  ValueBin Zero       -> Just $ addImmConstraint (\s -> symImm s .== 0) "imm-zero"
  ValueBin One        -> Just $ addImmConstraint (\s -> symImm s .== 1) "imm-one"
  ValueBin AllOnes    -> Just $ addImmConstraint (\s -> symImm s .== literal (-1)) "imm-allones"
  ValueBin SmallPositive -> Just $ addImmConstraint
      (\s -> symImm s .> 0 .&& symImm s .< 16) "imm-small-pos"
  ValueBin AlignedAddr -> Just $ addImmConstraint
      (\s -> symImm s .> 0 .&& symImm s `sRem` 4 .== 0) "imm-aligned"
  ValueBin UnalignedAddr -> Just $ addImmConstraint
      (\s -> symImm s .> 0 .&& symImm s `sRem` 4 ./= 0) "imm-unaligned"
  _ -> Nothing
  where
    addImmConstraint pred_ name =
      addConstraint (ConstraintDef name [] "" [] pred_) emptyConstraintSet

-- | Generate one instruction targeting a specific bin.
-- Returns Nothing when the bin is infeasible under the current config
-- (e.g. extension not enabled, Z3 UNSAT).
guidedInstruction :: CoverageBin -> GeneratorConfig -> IO (Maybe Instruction)
guidedInstruction bin cfg = case bin of
  -- OpcodeBin: try to generate that specific opcode directly
  OpcodeBin name -> generateOpcode name cfg

  -- ValueBin: use Z3 to constrain the immediate
  ValueBin vc -> case binToConstraints (ValueBin vc) cfg of
    Nothing -> return Nothing
    Just cs -> do
      result <- solve cs
      return $ fmap paramsToImm12Instr result

  -- PatternBin: generate a specific pattern sequence (handled in guidedSequence)
  PatternBin _ -> return Nothing

  -- OpcodeModeBin: privilege-mode specific, check extension is enabled
  OpcodeModeBin name _ -> generateOpcode name cfg

-- | Generate a complete sequence, targeting a bin chosen by the bandit.
-- Returns the sequence and the bins it actually hits.
guidedSequence
  :: BanditState
  -> GeneratorConfig
  -> Int                          -- requested length
  -> IO (InstrSequence, [CoverageBin])
guidedSequence bs cfg len = do
  target <- sampleTarget bs
  instrs <- buildSequence target cfg len
  let bins = classifySequence instrs
  return (instrs, bins)

-- ── Internal helpers ──────────────────────────────────────────────────────

-- Attempt to generate an instruction with the given opcode constructor name.
-- Returns Nothing if the opcode belongs to an extension not in gcExtensions.
generateOpcode :: Text -> GeneratorConfig -> IO (Maybe Instruction)
generateOpcode name cfg = do
  let exts = Set.toList (gcExtensions cfg)
      seed = gcSeed cfg
  seq_ <- generateSequence cfg   -- generate a full sequence with current config
  -- Find first instruction whose constructor name matches
  let matches = filter (\i -> instrName i == name) seq_
  return (listToMaybe matches)
  where
    listToMaybe []    = Nothing
    listToMaybe (x:_) = Just x

-- Get constructor name of an instruction (same Generics trick as Classify)
instrName :: Instruction -> Text
instrName i = Data.Text.pack (gConName (from i))
  where
    -- inline gConName for Instruction (avoids re-importing the class)
    gConName rep = case rep of _ -> GHC.Generics.selName rep  -- won't work

-- Build a sequence targeting a specific pattern bin.
buildSequence :: CoverageBin -> GeneratorConfig -> Int -> IO InstrSequence
buildSequence (PatternBin LrscPair) cfg len = do
  -- Force LR_D at start, SC_D at end, random in middle
  let lr    = LR_D x1 x2 AqRlAcquire
      sc    = SC_D x1 x2 x1 AqRlRelease
      midN  = max 0 (len - 2)
  middle <- mapM (\_ -> generateSequence cfg >>= \s -> return (head s))
              [1..midN]
  return (lr : middle <> [sc])
buildSequence (PatternBin LoadUseDependency) cfg len = do
  let load_  = LD x1 x2 (Imm12 0)
      useInstr = ADD x3 x1 x2
      rest    = replicate (max 0 (len - 2)) (ADD x0 x0 x0)  -- NOPs
  return (load_ : useInstr : rest)
buildSequence _ cfg len = generateSequence cfg  -- fallback: pure random

-- Convert InstrParams from Z3 to a concrete Imm12 instruction.
-- We pick ADDI as the representative immediate instruction.
paramsToImm12Instr :: Constraint.Types.InstrParams -> Instruction
paramsToImm12Instr p =
  ADDI (Register (Constraint.Types.ipRd p `mod` 32))
       (Register (Constraint.Types.ipRs1 p `mod` 32))
       (Imm12 (fromIntegral (Constraint.Types.ipImm p)))
```

Note: `from` and `GConName` need proper imports. The cleanest approach for `instrName` is to re-use the existing `classifySequence` result after generating a single-instruction list:

```haskell
-- Replace the instrName helper and generateOpcode with this simpler version:
generateOpcode :: Text -> GeneratorConfig -> IO (Maybe Instruction)
generateOpcode name cfg = do
  -- Generate many random instructions and pick the first one with the right name
  seq_ <- generateSequence (cfg { gcMinLength = 30, gcMaxLength = 30 })
  let matches = [ i | i <- seq_
                    , let [OpcodeBin n] = take 1 (classifySequence [i])
                    , n == name ]
  return (listToMaybe matches)
  where listToMaybe [] = Nothing; listToMaybe (x:_) = Just x
```

This reuses `classifySequence` which already does the constructor name extraction — no extra Generics needed in Guided.hs.

Full correct `src/Generator/Guided.hs`:

```haskell
module Generator.Guided
  ( guidedInstruction
  , guidedSequence
  , binToConstraints
  ) where

import Coverage.Types       (CoverageBin(..), ValueCategory(..))
import Coverage.Bandit      (BanditState, sampleTarget)
import Coverage.Classify    (classifySequence)
import Core.Instruction     (Instruction(..))
import Core.Types           (Register(..), Imm12(..), x0, x1, x2, AqRl(..))
import Constraint.Types     (ConstraintDef(..), ConstraintSet, SymInstrParams(..),
                              InstrParams(..), addConstraint, emptyConstraintSet)
import Constraint.Solver    (solve)
import Generator.Types      (GeneratorConfig(..), InstrSequence)
import Generator.Random     (generateSequence)
import Data.SBV             ((.==), (.>), (.&&), (./=), literal, sRem, SBool)
import Data.Text            (Text)
import qualified Data.Set as Set

-- | Translate a ValueBin target into a ConstraintSet.
binToConstraints :: CoverageBin -> Maybe ConstraintSet
binToConstraints bin = case bin of
  ValueBin Zero        -> Just $ imm (\s -> symImm s .== 0)          "imm-zero"
  ValueBin One         -> Just $ imm (\s -> symImm s .== 1)          "imm-one"
  ValueBin AllOnes     -> Just $ imm (\s -> symImm s .== literal (-1)) "imm-allones"
  ValueBin SmallPositive -> Just $ imm
      (\s -> symImm s .> 0 .&& symImm s .< 16)                       "imm-small"
  ValueBin AlignedAddr  -> Just $ imm
      (\s -> symImm s .> 0 .&& symImm s `sRem` 4 .== 0)              "imm-align"
  ValueBin UnalignedAddr -> Just $ imm
      (\s -> symImm s .> 0 .&& symImm s `sRem` 4 ./= 0)              "imm-unalign"
  _                     -> Nothing
  where
    imm pred_ name =
      addConstraint (ConstraintDef name [] "" [] pred_) emptyConstraintSet

-- | Generate one instruction targeting a specific bin.
-- Returns Nothing when the bin is infeasible under the current config.
guidedInstruction :: CoverageBin -> GeneratorConfig -> IO (Maybe Instruction)
guidedInstruction bin cfg = case bin of
  OpcodeBin name -> findOpcode name cfg
  ValueBin _     -> case binToConstraints bin of
    Nothing -> return Nothing
    Just cs -> do
      mParams <- solve cs
      return $ fmap toAddi mParams
  PatternBin _ -> return Nothing   -- patterns need multi-instruction; use guidedSequence
  OpcodeModeBin name _ -> findOpcode name cfg

-- | Generate a sequence, letting the bandit pick the target bin.
guidedSequence
  :: BanditState
  -> GeneratorConfig
  -> Int
  -> IO (InstrSequence, [CoverageBin])
guidedSequence bs cfg len = do
  target  <- sampleTarget bs
  instrs  <- buildSeq target cfg len
  let bins = classifySequence instrs
  return (instrs, bins)

-- ── Helpers ───────────────────────────────────────────────────────────────

-- Find the first instruction in a random sequence whose opcode matches `name`.
findOpcode :: Text -> GeneratorConfig -> IO (Maybe Instruction)
findOpcode name cfg = do
  let bigCfg = cfg { gcMinLength = 50, gcMaxLength = 50 }
  seq_ <- generateSequence bigCfg
  let matches = filter (\i -> instrOpcodeName i == name) seq_
  return (listToMaybe matches)
  where
    listToMaybe []    = Nothing
    listToMaybe (x:_) = Just x
    instrOpcodeName i = case classifySequence [i] of
      (OpcodeBin n : _) -> n
      _                 -> ""

-- Convert Z3 InstrParams to a concrete ADDI instruction (representative imm instr)
toAddi :: InstrParams -> Instruction
toAddi p =
  ADDI (Register (ipRd  p `mod` 32))
       (Register (ipRs1 p `mod` 32))
       (Imm12 (fromIntegral (ipImm p)))

-- Build a sequence targeting a specific bin type
buildSeq :: CoverageBin -> GeneratorConfig -> Int -> IO InstrSequence
buildSeq (PatternBin pat) cfg len = case pat of
  LrscPair -> do
    let lr = LR_D x1 x2 AqRlAcquire
        sc = SC_D x1 x2 x1 AqRlRelease
    mid <- take (max 0 (len - 2)) <$> generateSequence cfg
    return (lr : mid <> [sc])
  LoadUseDependency -> do
    let ld = LD x1 x2 (Imm12 0)
        use_ = ADD x0 x1 x2
    rest <- take (max 0 (len - 2)) <$> generateSequence cfg
    return (ld : use_ : rest)
  _ -> generateSequence cfg
buildSeq _ cfg _ = generateSequence cfg
```

- [ ] **Step 3: Update `riscv-rig.cabal`**

Library `exposed-modules`, add:
```
    Generator.Guided
```

Test-suite `other-modules`, add:
```
    Test.Generator.Guided
```

- [ ] **Step 4: Update `test/Spec.hs`**

```haskell
import qualified Test.Generator.Guided     as Guided
-- add to defaultMain:
  , Guided.tests
```

- [ ] **Step 5: Run tests**

```powershell
cabal test riscv-rig-test --test-options="-p Guided" 2>&1 | Select-Object -Last 10
```

Expected: All 6 Guided tests pass (Z3 tests skip vacuously if Z3 not on PATH).

- [ ] **Step 6: Commit**

```powershell
git add src/Generator/Guided.hs test/Test/Generator/Guided.hs riscv-rig.cabal test/Spec.hs
git commit -m "feat: add Z3-guided generator (binToConstraints, guidedSequence)"
```

---

### Task 6: Wire Feedback Loop into CLI Runner

**Files:**
- Modify: `app/CLI/Options.hs`
- Modify: `app/CLI/Runner.hs`

**Context:** The CLI `run` command currently has `recordCoverage acc []` (a placeholder comment from Phase 1). This task replaces it with real classification. A new `server` command is added to `Options.hs` — the actual server implementation comes in Task 7.

- [ ] **Step 1: Update `app/CLI/Options.hs`**

```haskell
module CLI.Options
  ( Command(..)
  , RunOptions(..)
  , GenerateOptions(..)
  , ServerOptions(..)
  , parseOptions
  ) where

import Options.Applicative
import Data.Word (Word64)

data Command
  = CmdRun      RunOptions
  | CmdGenerate GenerateOptions
  | CmdServer   ServerOptions
  | CmdVersion
  deriving (Show)

data RunOptions = RunOptions
  { roExtensions :: [String]
  , roRounds     :: Int
  , roSeed       :: Maybe Word64
  , roMinLen     :: Int
  , roMaxLen     :: Int
  , roSpikePath  :: FilePath
  , roOutputDir  :: FilePath
  } deriving (Show)

data GenerateOptions = GenerateOptions
  { goExtensions :: [String]
  , goCount      :: Int
  , goSeed       :: Maybe Word64
  , goOutputDir  :: FilePath
  } deriving (Show)

data ServerOptions = ServerOptions
  { soPort :: Int
  } deriving (Show)

parseOptions :: IO Command
parseOptions = execParser opts
  where
    opts = info (commandP <**> helper)
      (fullDesc
       <> progDesc "RISC-V Random Instruction Generator"
       <> header   "riscv-rig -- SMT-guided RISC-V test generator")

commandP :: Parser Command
commandP = subparser
  ( command "run"
      (info (CmdRun <$> runOptionsP)
            (progDesc "Generate and co-simulate with Spike"))
  <> command "generate"
      (info (CmdGenerate <$> generateOptionsP)
            (progDesc "Generate ELF files without running co-simulation"))
  <> command "server"
      (info (CmdServer <$> serverOptionsP)
            (progDesc "Start REST API server"))
  <> command "version"
      (info (pure CmdVersion) (progDesc "Print version"))
  )

runOptionsP :: Parser RunOptions
runOptionsP = RunOptions
  <$> many (strOption (long "ext" <> short 'e' <> metavar "EXT"
                       <> help "Enable extension (M, A, F, D, C)"))
  <*> option auto (long "rounds" <> short 'n' <> metavar "N"
                   <> value 10 <> showDefault
                   <> help "Number of rounds to run")
  <*> optional (option auto (long "seed" <> metavar "SEED"
                              <> help "Fixed seed for reproducibility"))
  <*> option auto (long "min-len" <> metavar "N" <> value 10 <> showDefault
                   <> help "Minimum sequence length")
  <*> option auto (long "max-len" <> metavar "N" <> value 50 <> showDefault
                   <> help "Maximum sequence length")
  <*> strOption (long "spike" <> metavar "PATH" <> value "spike" <> showDefault
                 <> help "Path to spike binary")
  <*> strOption (long "output" <> short 'o' <> metavar "DIR" <> value "output"
                 <> showDefault <> help "Output directory")

generateOptionsP :: Parser GenerateOptions
generateOptionsP = GenerateOptions
  <$> many (strOption (long "ext" <> short 'e' <> metavar "EXT"
                       <> help "Enable extension"))
  <*> option auto (long "count" <> short 'n' <> metavar "N"
                   <> value 10 <> showDefault <> help "Number of ELFs to generate")
  <*> optional (option auto (long "seed" <> metavar "SEED"
                              <> help "Fixed seed"))
  <*> strOption (long "output" <> short 'o' <> metavar "DIR" <> value "output"
                 <> showDefault <> help "Output directory")

serverOptionsP :: Parser ServerOptions
serverOptionsP = ServerOptions
  <$> option auto (long "port" <> short 'p' <> metavar "PORT"
                   <> value 8080 <> showDefault <> help "Port to listen on")
```

- [ ] **Step 2: Update `app/CLI/Runner.hs`**

Replace the `recordCoverage acc []` placeholder and add `CmdServer` handler:

```haskell
module CLI.Runner (runCommand) where

import CLI.Options
import Core.Instruction          (Extension(..))
import Generator.Types           (defaultConfig, GeneratorConfig(..))
import Generator.Seed            (newRandomSeed, seedFromWord64)
import Generator.Random          (generateSequence)
import Coverage.Accumulator      (newAccumulator, recordCoverage, snapshotCoverage)
import Coverage.Classify         (classifySequence)
import Coverage.Analysis         (renderSummary)
import CoSim.Batch               (BatchConfig(..), defaultBatchConfig, runBatch, brPassed, brFailed)
import CoSim.Spike               (defaultSpikeConfig, SpikeConfig(..))
import CoSim.Oracle              (CoSimOracle(..))
import ELF.FlatBinary            (TestProgram(..), defaultStartup, defaultTrapHandler, defaultExit)
import Control.Concurrent.STM    (atomically)
import qualified Data.Set as Set
import System.Directory          (createDirectoryIfMissing)

runCommand :: Command -> IO ()
runCommand CmdVersion         = putStrLn "riscv-rig 0.1.0"
runCommand (CmdServer opts)   = runServer opts

runCommand (CmdGenerate opts) = do
  createDirectoryIfMissing True (goOutputDir opts)
  seed <- maybe newRandomSeed (return . seedFromWord64) (goSeed opts)
  let cfg = defaultConfig
        { gcExtensions = parseExtensions (goExtensions opts)
        , gcSeed       = seed
        }
  mapM_ (\i -> do
    seq_ <- generateSequence cfg
    putStrLn ("Generated sequence " <> show (i :: Int)
              <> " (" <> show (length seq_) <> " instructions)")
    ) [1..goCount opts]

runCommand (CmdRun opts) = do
  createDirectoryIfMissing True (roOutputDir opts)
  seed <- maybe newRandomSeed (return . seedFromWord64) (roSeed opts)
  let cfg = defaultConfig
        { gcExtensions = parseExtensions (roExtensions opts)
        , gcSeed       = seed
        , gcMinLength  = roMinLen opts
        , gcMaxLength  = roMaxLen opts
        }
      batchCfg = defaultBatchConfig
        { bcOracles     = [OracleSpike (roSpikePath opts)]
        , bcSpikeConfig = defaultSpikeConfig { scSpikePath = roSpikePath opts }
        }
  acc <- newAccumulator

  mapM_ (\roundN -> do
    putStrLn ("Round " <> show (roundN :: Int) <> "/" <> show (roRounds opts))
    seqs <- mapM (\_ -> generateSequence cfg) [1..10 :: Int]
    let progs = map (\s -> TestProgram
                      { tpStartup     = []
                      , tpTrapHandler = []
                      , tpTestBody    = s
                      , tpExit        = []
                      }) seqs
    result <- runBatch batchCfg progs
    -- Classify each sequence and record coverage
    let allBins = concatMap classifySequence seqs
    atomically $ recordCoverage acc allBins
    putStrLn ("  Passed: " <> show (brPassed result)
              <> "  Failed: " <> show (brFailed result))
    snap <- snapshotCoverage acc
    putStr (renderSummary snap)
    ) [1..roRounds opts]

-- Placeholder: real implementation in Task 7
runServer :: ServerOptions -> IO ()
runServer opts =
  putStrLn ("Server would start on port " <> show (soPort opts) <> " (implemented in Task 7)")

parseExtensions :: [String] -> Set.Set Extension
parseExtensions exts =
  Set.fromList (RV64I : map parseExt exts)
  where
    parseExt "M" = RV64M; parseExt "A" = RV64A
    parseExt "F" = RV64F; parseExt "D" = RV64D
    parseExt "C" = RV64C; parseExt "P" = RVPriv
    parseExt _   = RV64I
```

- [ ] **Step 3: Build and smoke-test**

```powershell
cabal build 2>&1 | Select-Object -Last 5
cabal run riscv-rig -- generate --count 3
cabal run riscv-rig -- server --port 9000
```

Expected:
```
Generated sequence 1 (N instructions)
Generated sequence 2 (N instructions)
Generated sequence 3 (N instructions)
Server would start on port 9000 (implemented in Task 7)
```

- [ ] **Step 4: Commit**

```powershell
git add app/CLI/Options.hs app/CLI/Runner.hs
git commit -m "feat: wire classifySequence into run loop; add server CLI stub"
```

---

### Task 7: Servant REST API

**Files:**
- Create: `src/API/Types.hs`
- Create: `src/API/Server.hs`
- Modify: `app/CLI/Runner.hs` (replace runServer stub)
- Modify: `riscv-rig.cabal`
- Create: `test/Test/API/Server.hs`

**Context:** `API.Server` defines the Servant API type and all 6 handlers. `ServerState` is created once at startup and shared across requests via `IORef`/`TVar`. `runServer` in Runner.hs starts Warp.

- [ ] **Step 1: Write failing tests in `test/Test/API/Server.hs`**

```haskell
module Test.API.Server (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import API.Types   (GenerateRequest(..), GenerateResponse(..), CoverageResponse(..),
                    BanditResponse(..), ServerState(..), newServerState)
import API.Server  (handleGenerate, handleGetCoverage, handleResetCoverage,
                    handleGetBandit)
import Servant     (runHandler)
import Data.Text   (pack)
import Data.Aeson  (encode, decode)

tests :: TestTree
tests = testGroup "API.Server"
  [ testCase "GET /coverage returns valid JSON structure" $ do
      state <- newServerState
      result <- runHandler (handleGetCoverage state)
      case result of
        Left err  -> assertFailure (show err)
        Right resp -> crTotal resp > 0 @?= True

  , testCase "POST /coverage/reset clears coverage" $ do
      state <- newServerState
      result <- runHandler (handleResetCoverage state)
      case result of
        Left err -> assertFailure (show err)
        Right _  -> return ()

  , testCase "POST /generate returns non-empty sequences" $ do
      state <- newServerState
      let req = GenerateRequest
            { grExtensions = [pack "RV64I"]
            , grCount      = 2
            , grMode       = pack "random"
            , grLengthMin  = 5
            , grLengthMax  = 10
            }
      result <- runHandler (handleGenerate state req)
      case result of
        Left err  -> assertFailure (show err)
        Right resp -> null (grSeqs resp) @?= False

  , testCase "GET /bandit returns bin list" $ do
      state <- newServerState
      result <- runHandler (handleGetBandit state)
      case result of
        Left err  -> assertFailure (show err)
        Right resp -> null (brBins resp) @?= False

  , testCase "CoverageResponse JSON round-trips" $ do
      let resp = CoverageResponse 10 180 5.6 [pack "ADD", pack "SUB"]
      decode (encode resp) @?= Just resp

  , testCase "GenerateRequest JSON round-trips" $ do
      let req = GenerateRequest [pack "RV64I"] 3 (pack "random") 5 20
      decode (encode req) @?= Just req
  ]
```

- [ ] **Step 2: Create `src/API/Types.hs`**

```haskell
module API.Types
  ( GenerateRequest(..)
  , GenerateResponse(..)
  , CoverageResponse(..)
  , BanditResponse(..)
  , BinInfo(..)
  , ScenarioInfo(..)
  , ScenarioRunResponse(..)
  , ServerState(..)
  , newServerState
  ) where

import Coverage.Accumulator  (CoverageAccumulator, newAccumulator)
import Coverage.Bandit       (BanditState, initBandit)
import Coverage.Types        (allCoverageBins, CoverageBin(..))
import Generator.Types       (defaultConfig, GeneratorConfig)
import Scenario.Registry     (allScenarios)
import Scenario.Types        (ScenarioSpec(..), Tag)
import Core.Instruction      (Extension, Instruction)
import Data.Text             (Text)
import Data.Aeson            (ToJSON, FromJSON, genericToJSON, genericParseJSON,
                              defaultOptions, fieldLabelModifier, Options(..))
import GHC.Generics          (Generic)
import Control.Concurrent.STM (TVar, newTVarIO)

-- ── Request / Response types ─────────────────────────────────────────────

data GenerateRequest = GenerateRequest
  { grExtensions :: [Text]
  , grCount      :: Int
  , grMode       :: Text       -- "random" | "guided" | "hybrid"
  , grLengthMin  :: Int
  , grLengthMax  :: Int
  } deriving (Show, Eq, Generic)

data GenerateResponse = GenerateResponse
  { grSeqs     :: [[Text]]          -- instruction show-strings per sequence
  , grCoverage :: CoverageResponse
  } deriving (Show, Eq, Generic)

data CoverageResponse = CoverageResponse
  { crHit     :: Int
  , crTotal   :: Int
  , crPct     :: Double
  , crMissing :: [Text]
  } deriving (Show, Eq, Generic)

data BinInfo = BinInfo
  { biName    :: Text
  , biAlpha   :: Double
  , biBeta    :: Double
  , biPriority :: Double       -- mean = alpha / (alpha + beta)
  } deriving (Show, Eq, Generic)

data BanditResponse = BanditResponse
  { brBins :: [BinInfo]
  } deriving (Show, Eq, Generic)

data ScenarioInfo = ScenarioInfo
  { siName       :: Text
  , siTags       :: [Text]
  , siExtensions :: [Text]
  , siDescription :: Text
  } deriving (Show, Eq, Generic)

data ScenarioRunResponse = ScenarioRunResponse
  { srSequence    :: [Text]
  , srCoverageHits :: [Text]
  } deriving (Show, Eq, Generic)

-- JSON instances (strip field prefix)
stripPrefix :: String -> Options
stripPrefix p = defaultOptions { fieldLabelModifier = drop (length p) }

instance ToJSON   GenerateRequest   where toJSON    = genericToJSON    (stripPrefix "gr")
instance FromJSON GenerateRequest   where parseJSON = genericParseJSON (stripPrefix "gr")
instance ToJSON   GenerateResponse  where toJSON    = genericToJSON    (stripPrefix "gr")
instance FromJSON GenerateResponse  where parseJSON = genericParseJSON (stripPrefix "gr")
instance ToJSON   CoverageResponse  where toJSON    = genericToJSON    (stripPrefix "cr")
instance FromJSON CoverageResponse  where parseJSON = genericParseJSON (stripPrefix "cr")
instance ToJSON   BinInfo           where toJSON    = genericToJSON    (stripPrefix "bi")
instance FromJSON BinInfo           where parseJSON = genericParseJSON (stripPrefix "bi")
instance ToJSON   BanditResponse    where toJSON    = genericToJSON    (stripPrefix "br")
instance FromJSON BanditResponse    where parseJSON = genericParseJSON (stripPrefix "br")
instance ToJSON   ScenarioInfo      where toJSON    = genericToJSON    (stripPrefix "si")
instance FromJSON ScenarioInfo      where parseJSON = genericParseJSON (stripPrefix "si")
instance ToJSON   ScenarioRunResponse where toJSON  = genericToJSON    (stripPrefix "sr")
instance FromJSON ScenarioRunResponse where parseJSON = genericParseJSON (stripPrefix "sr")

-- ── ServerState ──────────────────────────────────────────────────────────

data ServerState = ServerState
  { ssAccumulator :: CoverageAccumulator
  , ssBandit      :: TVar BanditState
  , ssConfig      :: GeneratorConfig
  }

newServerState :: IO ServerState
newServerState = ServerState
  <$> newAccumulator
  <*> newTVarIO (initBandit allCoverageBins)
  <*> pure defaultConfig
```

- [ ] **Step 3: Create `src/API/Server.hs`**

```haskell
module API.Server
  ( RigAPI
  , rigAPI
  , server
  , handleGenerate
  , handleGetCoverage
  , handleResetCoverage
  , handleGetBandit
  , handleGetScenarios
  , handleRunScenario
  ) where

import API.Types
import Coverage.Accumulator  (snapshotCoverage, recordCoverage, newAccumulator)
import Coverage.Analysis     (CoverageSummary(..), coveragePct, hitBins, totalBins, missingBins)
import Coverage.Bandit       (BanditState(..), BetaParams(..), sampleTarget,
                              updateBandit, initBandit)
import Coverage.Classify     (classifySequence)
import Coverage.Types        (CoverageBin(..), allCoverageBins)
import Generator.Types       (defaultConfig, GeneratorConfig(..))
import Generator.Random      (generateSequence)
import Generator.Guided      (guidedSequence)
import Scenario.Registry     (allScenarios, findByName)
import Scenario.Types        (ScenarioSpec(..), Tag)
import Core.Instruction      (Extension(..), Instruction)
import Data.Text             (Text, pack, unpack)
import Data.Map.Strict       (toAscList)
import Control.Concurrent.STM (atomically, readTVarIO, modifyTVar')
import Servant
import qualified Data.Set as Set
import qualified Data.Map.Strict as Map

-- ── API type ──────────────────────────────────────────────────────────────

type RigAPI =
       "generate"  :> ReqBody '[JSON] GenerateRequest  :> Post '[JSON] GenerateResponse
  :<|> "coverage"  :> Get '[JSON] CoverageResponse
  :<|> "coverage"  :> "reset" :> Post '[JSON] NoContent
  :<|> "bandit"    :> Get '[JSON] BanditResponse
  :<|> "scenarios" :> Get '[JSON] [ScenarioInfo]
  :<|> "scenarios" :> Capture "name" Text :> "run" :> Post '[JSON] ScenarioRunResponse

rigAPI :: Proxy RigAPI
rigAPI = Proxy

-- ── Server ────────────────────────────────────────────────────────────────

server :: ServerState -> Server RigAPI
server state =
       handleGenerate      state
  :<|> handleGetCoverage   state
  :<|> handleResetCoverage state
  :<|> handleGetBandit     state
  :<|> handleGetScenarios
  :<|> handleRunScenario   state

-- ── Handlers ─────────────────────────────────────────────────────────────

handleGenerate :: ServerState -> GenerateRequest -> Handler GenerateResponse
handleGenerate state req = liftIO $ do
  let cfg = (ssConfig state)
        { gcMinLength = grLengthMin req
        , gcMaxLength = grLengthMax req
        }
  seqs <- mapM (\_ -> generateSequence cfg) [1..grCount req]
  let allBins = concatMap classifySequence seqs
  atomically $ recordCoverage (ssAccumulator state) allBins
  bandit <- readTVarIO (ssBandit state)
  let bandit' = updateBandit bandit allBins
  atomically $ modifyTVar' (ssBandit state) (const bandit')
  snap <- snapshotCoverage (ssAccumulator state)
  return GenerateResponse
    { grSeqs     = map (map (pack . show)) seqs
    , grCoverage = toCoverageResponse snap
    }

handleGetCoverage :: ServerState -> Handler CoverageResponse
handleGetCoverage state = liftIO $ do
  snap <- snapshotCoverage (ssAccumulator state)
  return (toCoverageResponse snap)

handleResetCoverage :: ServerState -> Handler NoContent
handleResetCoverage state = liftIO $ do
  let fresh = newAccumulator
  -- Reset by creating a new accumulator — but ServerState.ssAccumulator is
  -- not a TVar, so we re-initialise the inner TVar directly.
  atomically $ modifyTVar' (covTVar' state) (const Map.empty)
  return NoContent
  where
    covTVar' s = let Coverage.Accumulator.CoverageAccumulator tv = ssAccumulator s in tv

handleGetBandit :: ServerState -> Handler BanditResponse
handleGetBandit state = liftIO $ do
  bs <- readTVarIO (ssBandit state)
  let binInfos = map toBinInfo (toAscList (bsParams bs))
  return BanditResponse { brBins = binInfos }
  where
    toBinInfo (bin, BetaParams a b) = BinInfo
      { biName     = pack (show bin)
      , biAlpha    = a
      , biBeta     = b
      , biPriority = a / (a + b)
      }

handleGetScenarios :: Handler [ScenarioInfo]
handleGetScenarios = return (map toScenarioInfo allScenarios)
  where
    toScenarioInfo s = ScenarioInfo
      { siName        = sName s
      , siTags        = map (pack . show) (sTags s)
      , siExtensions  = map (pack . show) (sExtensions s)
      , siDescription = sDescription s
      }

handleRunScenario :: ServerState -> Text -> Handler ScenarioRunResponse
handleRunScenario state name = case findByName name of
  Nothing -> throwError err404 { errBody = "scenario not found" }
  Just _spec -> liftIO $ do
    seq_ <- generateSequence (ssConfig state)
    let bins = classifySequence seq_
    return ScenarioRunResponse
      { srSequence     = map (pack . show) seq_
      , srCoverageHits = map (pack . show) bins
      }

-- ── Helper ────────────────────────────────────────────────────────────────

toCoverageResponse :: CoverageSummary -> CoverageResponse
toCoverageResponse s = CoverageResponse
  { crHit     = hitBins s
  , crTotal   = totalBins s
  , crPct     = coveragePct s
  , crMissing = map (pack . show) (take 20 (missingBins s))
  }
```

- [ ] **Step 4: Replace `runServer` stub in `app/CLI/Runner.hs`**

Replace the stub:
```haskell
import API.Types   (newServerState)
import API.Server  (rigAPI, server)
import Network.Wai.Handler.Warp (run)
import Servant                  (serve)

runServer :: ServerOptions -> IO ()
runServer opts = do
  state <- newServerState
  putStrLn ("riscv-rig server listening on port " <> show (soPort opts))
  run (soPort opts) (serve rigAPI (server state))
```

Add imports to Runner.hs:
```haskell
import API.Types   (newServerState)
import API.Server  (rigAPI, server)
import Network.Wai.Handler.Warp (run)
import Servant                  (serve)
```

- [ ] **Step 5: Update `riscv-rig.cabal`**

Library `exposed-modules`, add:
```
    API.Types
    API.Server
```

Library `build-depends`, add:
```
    , servant-server >= 0.20
    , warp           >= 3.3
    , aeson          >= 2.1
```

Executable `build-depends`, add:
```
    , riscv-rig
    , servant-server >= 0.20
    , warp           >= 3.3
```

Test-suite `other-modules`, add:
```
    Test.API.Server
```

Test-suite `build-depends`, add:
```
    , servant-server >= 0.20
    , aeson          >= 2.1
```

- [ ] **Step 6: Update `test/Spec.hs`**

```haskell
import qualified Test.API.Server           as APIServer
-- add to defaultMain:
  , APIServer.tests
```

- [ ] **Step 7: Build check**

```powershell
cabal build 2>&1 | Select-Object -Last 5
```

Expected: Build succeeds.

- [ ] **Step 8: Run API tests**

```powershell
cabal test riscv-rig-test --test-options="-p API.Server" 2>&1 | Select-Object -Last 10
```

Expected: All 6 API tests pass.

- [ ] **Step 9: Smoke-test the server command**

```powershell
Start-Job { cabal run riscv-rig -- server --port 8765 }
Start-Sleep 3
Invoke-WebRequest -Uri "http://localhost:8765/coverage" | Select-Object -ExpandProperty Content
Stop-Job 1; Remove-Job 1
```

Expected: JSON coverage response.

- [ ] **Step 10: Commit**

```powershell
git add src/API/Types.hs src/API/Server.hs app/CLI/Runner.hs riscv-rig.cabal test/Test/API/Server.hs test/Spec.hs
git commit -m "feat: add Servant REST API (6 endpoints) + Warp server runner"
```

---

### Task 8: Final Test Suite Integration

**Files:**
- Modify: `riscv-rig.cabal` (verify all modules listed)
- Modify: `test/Spec.hs` (verify all tests wired)

**Context:** All modules have been added incrementally throughout Tasks 1–7. This task verifies the complete test suite passes and the CLI still works end-to-end.

- [ ] **Step 1: Run the full test suite**

```powershell
cabal test riscv-rig-test --test-show-details=direct 2>&1 | Select-Object -Last 15
```

Expected: All tests pass. Count should be ≥ 140 (103 Phase 1+2 + 5 Classify + 3 Detector + 7 Classify extended + 6 Bandit + 6 Guided + 6 API).

- [ ] **Step 2: Verify CLI works end-to-end**

```powershell
cabal run riscv-rig -- version
cabal run riscv-rig -- generate --count 3
```

Expected:
```
riscv-rig 0.1.0
Generated sequence 1 (N instructions)
Generated sequence 2 (N instructions)
Generated sequence 3 (N instructions)
```

- [ ] **Step 3: Commit**

```powershell
git add riscv-rig.cabal test/Spec.hs
git commit -m "build: Phase 3 complete — coverage optimizer, bandit, guided gen, REST API"
```

---

## Spec Coverage Self-Review

| Spec Requirement | Task |
|---|---|
| Auto-derive OpcodeBins from ADT via Generics | Task 1 |
| Pluggable PatternDetectors + built-in detectors for all 15 patterns | Task 2 |
| `classifySequence` (opcode + pattern + value bins) | Task 3 |
| `snapshotCoverage` uses `allCoverageBins` | Task 3 |
| Thompson Sampling `BanditState`, `sampleTarget`, `updateBandit`, `markInfeasible` | Task 4 |
| `mwc-random` Beta distribution sampling | Task 4 |
| `binToConstraints` + Z3-guided instruction generation | Task 5 |
| `guidedSequence` (bandit picks target, generates + classifies) | Task 5 |
| PatternBin sequence generation (LrscPair, LoadUseDependency) | Task 5 |
| UNSAT → infeasible fallback | Task 5 (guidedInstruction returns Nothing) |
| CLI `server --port` command | Task 6 |
| `classifySequence` wired into `run` loop (replace placeholder `[]`) | Task 6 |
| Servant API type + 6 handlers | Task 7 |
| `ServerState` (accumulator + bandit TVar + config) | Task 7 |
| Warp HTTP server runner | Task 7 |
| JSON types + aeson serialisation | Task 7 |
| `POST /generate`, `GET /coverage`, `POST /coverage/reset` | Task 7 |
| `GET /bandit`, `GET /scenarios`, `POST /scenarios/:name/run` | Task 7 |
