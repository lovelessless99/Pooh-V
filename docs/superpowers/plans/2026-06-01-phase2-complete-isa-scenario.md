# Phase 2: Complete ISA + Scenario Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend riscv-rig Phase 1 (RV64I+M) with RV64A/F/D/C instruction extensions, Scenario DSL, extension dependency resolution, PMA memory model, CoSim shrinking, and Sail oracle integration.

**Architecture:** All ISA extensions are additive to the existing `Core.Instruction` sum type; encode/decode follow the same `buildR`/`buildI` helper pattern. New modules `Core.ExtDeps`, `Core.PMA`, `CoSim.Shrink`, `Scenario.*`, and `CoSim.Sail` are independent of each other and can be implemented in parallel. Generator and Coverage are updated after the ISA extensions.

**Tech Stack:** GHC 9.4.8, GHC2021, SBV 10.2 (Z3), Hedgehog 1.4, Data.Bits, Data.Map, Data.Set, Control.Monad.State (Scenario DSL)

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `src/Core/Types.hs` | Modify | Add UImm7/8/9/10, Imm9/10, FP register aliases |
| `src/Core/Instruction.hs` | Modify | Add RV64A/F/D/C constructors + Extension enum |
| `src/Core/Encode.hs` | Modify | Add atomic / FP / compressed encode cases |
| `src/Core/Decode.hs` | Modify | Add atomic / FP decode cases + `decode16` |
| `src/Generator/Random.hs` | Modify | Add OpcodeCategory for A/F/D/C |
| `src/Coverage/Types.hs` | Modify | Add SequencePattern, ValueCategory, PatternBin, ValueBin, OpcodeModeBin |
| `src/Core/ExtDeps.hs` | Create | Extension dependency graph |
| `src/Core/PMA.hs` | Create | Physical Memory Attributes model |
| `src/CoSim/Shrink.hs` | Create | Delta-debugging shrink for mismatch sequences |
| `src/CoSim/Sail.hs` | Create | Sail ISA simulator runner (mirrors Spike) |
| `src/Scenario/Types.hs` | Create | ScenarioSpec, ScenarioPhase, Event, Directive |
| `src/Scenario/Registry.hs` | Create | Manual scenario registry |
| `src/Scenario/Builtin/LrscInterrupt.hs` | Create | Example LR/SC + interrupt scenario |
| `riscv-rig.cabal` | Modify | Expose all new modules |
| `test/Spec.hs` | Modify | Add new test modules |
| `test/Test/Core/Atomic.hs` | Create | RV64A encode/decode tests |
| `test/Test/Core/FloatInstr.hs` | Create | RV64F+D encode/decode tests |
| `test/Test/Core/Compressed.hs` | Create | RV64C encode16/decode16 tests |
| `test/Test/Core/ExtDeps.hs` | Create | Extension dependency tests |
| `test/Test/Core/PMA.hs` | Create | PMA lookup tests |
| `test/Test/Coverage/Bins.hs` | Create | New bin type tests |
| `test/Test/CoSim/Shrink.hs` | Create | Shrinking tests |
| `test/Test/Scenario/Registry.hs` | Create | Scenario registry tests |

---

### Task 1: Extension ADT + New Primitive Types

**Files:**
- Modify: `src/Core/Instruction.hs` (lines 14–18, Extension enum)
- Modify: `src/Core/Types.hs` (add types, add FP register aliases)

**Context:** Phase 1 has `Extension = RV64I | RV64M | RVPriv`. All Phase 2 ISA tasks depend on the new extension constructors. `FPRegister` already exists in `Core.Types` but has no register aliases. The new immediate types are needed for RV64C instruction constructors in Task 5.

- [ ] **Step 1: Add RV64A/F/D/C to Extension enum in `src/Core/Instruction.hs`**

Replace the existing Extension definition (currently lines 14–18):

```haskell
data Extension
  = RV64I
  | RV64M
  | RV64A
  | RV64F
  | RV64D
  | RV64C
  | RVPriv
  deriving (Show, Eq, Ord, Enum, Bounded, Generic)
```

- [ ] **Step 2: Add new immediate types and FP register aliases to `src/Core/Types.hs`**

After the existing `newtype UImm6` line, add:

```haskell
-- New types for RV64C compressed immediates
newtype UImm7  = UImm7  { unUImm7  :: Word8  } deriving (Show, Eq, Ord, Generic)
newtype UImm8  = UImm8  { unUImm8  :: Word8  } deriving (Show, Eq, Ord, Generic)
newtype UImm9  = UImm9  { unUImm9  :: Word16 } deriving (Show, Eq, Ord, Generic)
newtype UImm10 = UImm10 { unUImm10 :: Word16 } deriving (Show, Eq, Ord, Generic)
newtype Imm9   = Imm9   { unImm9   :: Int16  } deriving (Show, Eq, Ord, Generic)
newtype Imm10  = Imm10  { unImm10  :: Int16  } deriving (Show, Eq, Ord, Generic)
```

Then, after the existing integer register aliases (x31), add FP register aliases:

```haskell
-- FP register aliases (RISC-V ABI names)
ft0, ft1, ft2, ft3, ft4, ft5, ft6, ft7 :: FPRegister
fs0, fs1                                :: FPRegister
fa0, fa1, fa2, fa3, fa4, fa5, fa6, fa7 :: FPRegister
fs2, fs3, fs4, fs5, fs6, fs7, fs8, fs9, fs10, fs11 :: FPRegister
ft8, ft9, ft10, ft11                    :: FPRegister
ft0  = FPRegister  0; ft1  = FPRegister  1; ft2  = FPRegister  2
ft3  = FPRegister  3; ft4  = FPRegister  4; ft5  = FPRegister  5
ft6  = FPRegister  6; ft7  = FPRegister  7; fs0  = FPRegister  8
fs1  = FPRegister  9; fa0  = FPRegister 10; fa1  = FPRegister 11
fa2  = FPRegister 12; fa3  = FPRegister 13; fa4  = FPRegister 14
fa5  = FPRegister 15; fa6  = FPRegister 16; fa7  = FPRegister 17
fs2  = FPRegister 18; fs3  = FPRegister 19; fs4  = FPRegister 20
fs5  = FPRegister 21; fs6  = FPRegister 22; fs7  = FPRegister 23
fs8  = FPRegister 24; fs9  = FPRegister 25; fs10 = FPRegister 26
fs11 = FPRegister 27; ft8  = FPRegister 28; ft9  = FPRegister 29
ft10 = FPRegister 30; ft11 = FPRegister 31
```

Update the `Core.Types` module export list to include all new types and aliases:

```haskell
module Core.Types
  ( Register(..), FPRegister(..), CSRAddr(..)
  , Imm12(..), Imm13(..), Imm20(..), Imm21(..), Imm6(..), Imm9(..), Imm10(..)
  , UImm5(..), UImm6(..), UImm7(..), UImm8(..), UImm9(..), UImm10(..)
  , AqRl(..), RoundingMode(..), FenceMode(..)
  , PrivilegeLevel(..)
  -- Integer register aliases (ABI names)
  , x0, ra, sp, gp, tp, t0, t1, t2, fp, s1
  , a0, a1, a2, a3, a4, a5, a6, a7
  , s2, s3, s4, s5, s6, s7, s8, s9, s10, s11
  , t3, t4, t5, t6
  , x1, x2, x3, x4, x5, x6, x7, x8, x9, x10
  , x11, x12, x13, x14, x15, x16, x17, x18, x19, x20
  , x21, x22, x23, x24, x25, x26, x27, x28, x29, x30, x31
  -- FP register aliases
  , ft0, ft1, ft2, ft3, ft4, ft5, ft6, ft7
  , fs0, fs1
  , fa0, fa1, fa2, fa3, fa4, fa5, fa6, fa7
  , fs2, fs3, fs4, fs5, fs6, fs7, fs8, fs9, fs10, fs11
  , ft8, ft9, ft10, ft11
  ) where
```

Also add `Data.Word (Word16)` to the import (already present), and add `Data.Int (Int16)` if not already present.

- [ ] **Step 3: Verify it compiles**

```bash
cabal build 2>&1 | tail -5
```

Expected: `Build succeeded` or only warnings about unused constructors (new extension variants not yet used). Do not proceed if there are errors.

- [ ] **Step 4: Commit**

```bash
git add src/Core/Types.hs src/Core/Instruction.hs
git commit -m "feat: add RV64A/F/D/C to Extension enum; add compressed immediate types and FP register aliases"
```

---

### Task 2: RV64A — Atomic Instructions

**Files:**
- Modify: `src/Core/Instruction.hs`
- Modify: `src/Core/Encode.hs`
- Modify: `src/Core/Decode.hs`
- Create: `test/Test/Core/Atomic.hs`

**Context:** RV64A adds LR/SC and AMO instructions. All use opcode `0x2F`. The instruction format has `funct5 | aq | rl | rs2 | rs1 | funct3 | rd | 0x2F`. For LR, `rs2 = 00000`. `AqRl` type already exists in `Core.Types`. Argument order in ADT: `rd rs1 rs2 AqRl` (for SC/AMO) and `rd rs1 AqRl` (for LR).

- [ ] **Step 1: Write failing tests in `test/Test/Core/Atomic.hs`**

```haskell
module Test.Core.Atomic (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Core.Types
import Core.Instruction
import Core.Encode  (encode)
import Core.Decode  (decode)

tests :: TestTree
tests = testGroup "RV64A"
  [ testCase "LR_W encode opcode is 0x2F" $ do
      let w = encode (LR_W x1 x2 AqRlNone)
      (w .&. 0x7F) @?= 0x2F

  , testCase "LR_W funct3=010 (word)" $ do
      let w = encode (LR_W x1 x2 AqRlNone)
      ((w `shiftR` 12) .&. 0x7) @?= 0x2

  , testCase "LR_D funct3=011 (double)" $ do
      let w = encode (LR_D x1 x2 AqRlAcquire)
      ((w `shiftR` 12) .&. 0x7) @?= 0x3

  , testCase "LR_W aq=0 rl=0 for AqRlNone" $ do
      let w = encode (LR_W x1 x2 AqRlNone)
      ((w `shiftR` 25) .&. 0x3) @?= 0x0

  , testCase "LR_W aq=1 rl=1 for AqRlAcqRel" $ do
      let w = encode (LR_W x1 x2 AqRlAcqRel)
      ((w `shiftR` 25) .&. 0x3) @?= 0x3

  , testCase "SC_W funct5=00011" $ do
      let w = encode (SC_W x1 x2 x3 AqRlNone)
      ((w `shiftR` 27) .&. 0x1F) @?= 0x03

  , testCase "AMOADD_W funct5=00000" $ do
      let w = encode (AMOADD_W x1 x2 x3 AqRlNone)
      ((w `shiftR` 27) .&. 0x1F) @?= 0x00

  , testCase "AMOSWAP_W funct5=00001" $ do
      let w = encode (AMOSWAP_W x1 x2 x3 AqRlNone)
      ((w `shiftR` 27) .&. 0x1F) @?= 0x01

  , testCase "AMOADD_W encode/decode round-trip" $ do
      let instr = AMOADD_W x5 x6 x7 AqRlRelease
      decode (encode instr) @?= Right instr

  , testCase "AMOSWAP_D encode/decode round-trip" $ do
      let instr = AMOSWAP_D x1 x2 x3 AqRlAcqRel
      decode (encode instr) @?= Right instr
  ]
  where
    (.&.) = (Data.Bits..&.)
    shiftR = Data.Bits.shiftR
```

Add `import Data.Bits` at the top.

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cabal test riscv-rig-test --test-options="--pattern=RV64A" 2>&1 | tail -10
```

Expected: compilation errors (LR_W, SC_W not yet defined).

- [ ] **Step 3: Add atomic constructors to `src/Core/Instruction.hs`**

After the `-- ── Privileged` section and before `deriving (Show, Eq, Ord, Generic)`, add:

```haskell
  -- ── RV64A: Load-Reserved / Store-Conditional ────────────────────
  | LR_W      Register Register AqRl          -- rd rs1 aqrl
  | LR_D      Register Register AqRl
  | SC_W      Register Register Register AqRl  -- rd rs1 rs2 aqrl
  | SC_D      Register Register Register AqRl
  -- ── RV64A: Atomic Memory Operations (word) ─────────────────────
  | AMOSWAP_W Register Register Register AqRl  -- rd rs1 rs2 aqrl
  | AMOADD_W  Register Register Register AqRl
  | AMOXOR_W  Register Register Register AqRl
  | AMOAND_W  Register Register Register AqRl
  | AMOOR_W   Register Register Register AqRl
  | AMOMIN_W  Register Register Register AqRl
  | AMOMAX_W  Register Register Register AqRl
  | AMOMINU_W Register Register Register AqRl
  | AMOMAXU_W Register Register Register AqRl
  -- ── RV64A: Atomic Memory Operations (double) ───────────────────
  | AMOSWAP_D Register Register Register AqRl
  | AMOADD_D  Register Register Register AqRl
  | AMOXOR_D  Register Register Register AqRl
  | AMOAND_D  Register Register Register AqRl
  | AMOOR_D   Register Register Register AqRl
  | AMOMIN_D  Register Register Register AqRl
  | AMOMAX_D  Register Register Register AqRl
  | AMOMINU_D Register Register Register AqRl
  | AMOMAXU_D Register Register Register AqRl
```

Update `instrExtension`:

```haskell
instrExtension instr = case instr of
  -- existing MUL etc -> RV64M
  LR_W{}      -> RV64A; LR_D{}      -> RV64A
  SC_W{}      -> RV64A; SC_D{}      -> RV64A
  AMOSWAP_W{} -> RV64A; AMOADD_W{}  -> RV64A; AMOXOR_W{}  -> RV64A
  AMOAND_W{}  -> RV64A; AMOOR_W{}   -> RV64A; AMOMIN_W{}  -> RV64A
  AMOMAX_W{}  -> RV64A; AMOMINU_W{} -> RV64A; AMOMAXU_W{} -> RV64A
  AMOSWAP_D{} -> RV64A; AMOADD_D{}  -> RV64A; AMOXOR_D{}  -> RV64A
  AMOAND_D{}  -> RV64A; AMOOR_D{}   -> RV64A; AMOMIN_D{}  -> RV64A
  AMOMAX_D{}  -> RV64A; AMOMINU_D{} -> RV64A; AMOMAXU_D{} -> RV64A
  -- existing MRET etc -> RVPriv
  _           -> RV64I
```

Update `instrFormat` (all atomics are R-format):

```haskell
  LR_W{} -> RFormat; LR_D{} -> RFormat
  SC_W{} -> RFormat; SC_D{} -> RFormat
  AMOSWAP_W{} -> RFormat; AMOADD_W{}  -> RFormat; AMOXOR_W{}  -> RFormat
  AMOAND_W{}  -> RFormat; AMOOR_W{}   -> RFormat; AMOMIN_W{}  -> RFormat
  AMOMAX_W{}  -> RFormat; AMOMINU_W{} -> RFormat; AMOMAXU_W{} -> RFormat
  AMOSWAP_D{} -> RFormat; AMOADD_D{}  -> RFormat; AMOXOR_D{}  -> RFormat
  AMOAND_D{}  -> RFormat; AMOOR_D{}   -> RFormat; AMOMIN_D{}  -> RFormat
  AMOMAX_D{}  -> RFormat; AMOMINU_D{} -> RFormat; AMOMAXU_D{} -> RFormat
```

Update `requiresExtensions`:

```haskell
requiresExtensions i = case instrExtension i of
  RV64A -> [RV64A, RV64I]
  RV64F -> [RV64F, RV64I]
  RV64D -> [RV64D, RV64F, RV64I]
  RV64C -> [RV64C, RV64I]
  e     -> [e]
```

- [ ] **Step 4: Add atomic encode to `src/Core/Encode.hs`**

Add helper functions after the existing helpers at the top of encode.hs:

```haskell
encodeAqRl :: AqRl -> (Word32, Word32)  -- (aq, rl)
encodeAqRl AqRlNone    = (0, 0)
encodeAqRl AqRlRelease = (0, 1)
encodeAqRl AqRlAcquire = (1, 0)
encodeAqRl AqRlAcqRel  = (1, 1)

-- Atomic Memory Operation: opcode=0x2F
-- funct5 aq rl rs2 rs1 funct3 rd
buildAMO :: Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32
buildAMO funct5 aq rl rs2W rs1W funct3 rdW =
  (funct5 `shiftL` 27) .|. (aq `shiftL` 26) .|. (rl `shiftL` 25)
  .|. (rs2W `shiftL` 20) .|. (rs1W `shiftL` 15)
  .|. (funct3 `shiftL` 12) .|. (rdW `shiftL` 7) .|. 0x2F
```

Add encode cases (append to the `encode = \case` block):

```haskell
  -- ── RV64A ─────────────────────────────────────────────────────
  LR_W  rd rs1 aq    -> let (a,l) = encodeAqRl aq in buildAMO 0x02 a l 0       (r rs1) 0x2 (r rd)
  LR_D  rd rs1 aq    -> let (a,l) = encodeAqRl aq in buildAMO 0x02 a l 0       (r rs1) 0x3 (r rd)
  SC_W  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x03 a l (r rs2) (r rs1) 0x2 (r rd)
  SC_D  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x03 a l (r rs2) (r rs1) 0x3 (r rd)
  AMOSWAP_W rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x01 a l (r rs2) (r rs1) 0x2 (r rd)
  AMOADD_W  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x00 a l (r rs2) (r rs1) 0x2 (r rd)
  AMOXOR_W  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x04 a l (r rs2) (r rs1) 0x2 (r rd)
  AMOAND_W  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x0C a l (r rs2) (r rs1) 0x2 (r rd)
  AMOOR_W   rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x08 a l (r rs2) (r rs1) 0x2 (r rd)
  AMOMIN_W  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x10 a l (r rs2) (r rs1) 0x2 (r rd)
  AMOMAX_W  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x14 a l (r rs2) (r rs1) 0x2 (r rd)
  AMOMINU_W rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x18 a l (r rs2) (r rs1) 0x2 (r rd)
  AMOMAXU_W rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x1C a l (r rs2) (r rs1) 0x2 (r rd)
  AMOSWAP_D rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x01 a l (r rs2) (r rs1) 0x3 (r rd)
  AMOADD_D  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x00 a l (r rs2) (r rs1) 0x3 (r rd)
  AMOXOR_D  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x04 a l (r rs2) (r rs1) 0x3 (r rd)
  AMOAND_D  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x0C a l (r rs2) (r rs1) 0x3 (r rd)
  AMOOR_D   rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x08 a l (r rs2) (r rs1) 0x3 (r rd)
  AMOMIN_D  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x10 a l (r rs2) (r rs1) 0x3 (r rd)
  AMOMAX_D  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x14 a l (r rs2) (r rs1) 0x3 (r rd)
  AMOMINU_D rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x18 a l (r rs2) (r rs1) 0x3 (r rd)
  AMOMAXU_D rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x1C a l (r rs2) (r rs1) 0x3 (r rd)
```

- [ ] **Step 5: Add atomic decode to `src/Core/Decode.hs`**

Add `0x2F` to the decode dispatch and a new helper:

```haskell
-- In decode function, add after 0x73 case:
  0x2F -> decodeAMO w
```

Add the helper:

```haskell
decodeAqRl :: Word32 -> AqRl
decodeAqRl w = case (field w 26 26, field w 25 25) of
  (0, 0) -> AqRlNone
  (0, 1) -> AqRlRelease
  (1, 0) -> AqRlAcquire
  _      -> AqRlAcqRel

decodeAMO :: Word32 -> Either DecodeError Instruction
decodeAMO w =
  let funct5 = field w 31 27
      funct3 = funct3' w
      rd_    = mkReg (rd' w)
      rs1_   = mkReg (rs1' w)
      rs2_   = mkReg (rs2' w)
      aqrl   = decodeAqRl w
  in case (funct3, funct5) of
    (0x2, 0x02) -> Right $ LR_W  rd_ rs1_ aqrl
    (0x3, 0x02) -> Right $ LR_D  rd_ rs1_ aqrl
    (0x2, 0x03) -> Right $ SC_W  rd_ rs1_ rs2_ aqrl
    (0x3, 0x03) -> Right $ SC_D  rd_ rs1_ rs2_ aqrl
    (0x2, 0x01) -> Right $ AMOSWAP_W rd_ rs1_ rs2_ aqrl
    (0x2, 0x00) -> Right $ AMOADD_W  rd_ rs1_ rs2_ aqrl
    (0x2, 0x04) -> Right $ AMOXOR_W  rd_ rs1_ rs2_ aqrl
    (0x2, 0x0C) -> Right $ AMOAND_W  rd_ rs1_ rs2_ aqrl
    (0x2, 0x08) -> Right $ AMOOR_W   rd_ rs1_ rs2_ aqrl
    (0x2, 0x10) -> Right $ AMOMIN_W  rd_ rs1_ rs2_ aqrl
    (0x2, 0x14) -> Right $ AMOMAX_W  rd_ rs1_ rs2_ aqrl
    (0x2, 0x18) -> Right $ AMOMINU_W rd_ rs1_ rs2_ aqrl
    (0x2, 0x1C) -> Right $ AMOMAXU_W rd_ rs1_ rs2_ aqrl
    (0x3, 0x01) -> Right $ AMOSWAP_D rd_ rs1_ rs2_ aqrl
    (0x3, 0x00) -> Right $ AMOADD_D  rd_ rs1_ rs2_ aqrl
    (0x3, 0x04) -> Right $ AMOXOR_D  rd_ rs1_ rs2_ aqrl
    (0x3, 0x0C) -> Right $ AMOAND_D  rd_ rs1_ rs2_ aqrl
    (0x3, 0x08) -> Right $ AMOOR_D   rd_ rs1_ rs2_ aqrl
    (0x3, 0x10) -> Right $ AMOMIN_D  rd_ rs1_ rs2_ aqrl
    (0x3, 0x14) -> Right $ AMOMAX_D  rd_ rs1_ rs2_ aqrl
    (0x3, 0x18) -> Right $ AMOMINU_D rd_ rs1_ rs2_ aqrl
    (0x3, 0x1C) -> Right $ AMOMAXU_D rd_ rs1_ rs2_ aqrl
    _           -> Left  $ UnknownFunct3 0x2F funct3
```

- [ ] **Step 6: Run tests**

```bash
cabal test riscv-rig-test --test-options="--pattern=RV64A" 2>&1 | tail -10
```

Expected: All RV64A tests pass.

- [ ] **Step 7: Commit**

```bash
git add src/Core/Instruction.hs src/Core/Encode.hs src/Core/Decode.hs test/Test/Core/Atomic.hs
git commit -m "feat: add RV64A atomic instructions (LR/SC/AMO) with encode/decode"
```

---

### Task 3: RV64F — Single-Precision Float Instructions

**Files:**
- Modify: `src/Core/Instruction.hs`
- Modify: `src/Core/Encode.hs`
- Modify: `src/Core/Decode.hs`
- Create: `test/Test/Core/FloatInstr.hs`

**Context:** FP instructions use opcode `0x53` (OP-FP). Load uses `0x07`, store `0x27`. FMADD/FMSUB/FNMADD/FNMSUB use R4 format with opcodes `0x43/0x47/0x4B/0x4F`. The `funct7` encodes both operation and precision: bits [1:0] = `00` for single, `01` for double. `RoundingMode` already exists in `Core.Types`. `FPRegister` already exists. Argument order: `rd rs1 rs2 RoundingMode` for 3-operand FP.

- [ ] **Step 1: Write failing tests in `test/Test/Core/FloatInstr.hs`**

```haskell
module Test.Core.FloatInstr (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Core.Types
import Core.Instruction
import Core.Encode  (encode)
import Core.Decode  (decode)
import Data.Bits    (shiftR, (.&.))

tests :: TestTree
tests = testGroup "RV64F+D"
  [ testCase "FLW opcode=0x07 funct3=010" $ do
      let w = encode (FLW fa0 x1 (Imm12 0))
      (w .&. 0x7F) @?= 0x07
      ((w `shiftR` 12) .&. 0x7) @?= 0x2

  , testCase "FSW opcode=0x27 funct3=010" $ do
      let w = encode (FSW fa0 x1 (Imm12 0))
      (w .&. 0x7F) @?= 0x27
      ((w `shiftR` 12) .&. 0x7) @?= 0x2

  , testCase "FADD_S funct7=0x00" $ do
      let w = encode (FADD_S fa0 fa1 fa2 RNE)
      ((w `shiftR` 25) .&. 0x7F) @?= 0x00

  , testCase "FADD_D funct7=0x01" $ do
      let w = encode (FADD_D fa0 fa1 fa2 RNE)
      ((w `shiftR` 25) .&. 0x7F) @?= 0x01

  , testCase "FMADD_S opcode=0x43 funct2=00" $ do
      let w = encode (FMADD_S fa0 fa1 fa2 fa3 RNE)
      (w .&. 0x7F) @?= 0x43
      ((w `shiftR` 25) .&. 0x3) @?= 0x0

  , testCase "FMADD_D funct2=01" $ do
      let w = encode (FMADD_D fa0 fa1 fa2 fa3 RNE)
      ((w `shiftR` 25) .&. 0x3) @?= 0x1

  , testCase "FADD_S encode/decode round-trip" $ do
      let instr = FADD_S fa1 fa2 fa3 RTZ
      decode (encode instr) @?= Right instr

  , testCase "FLW encode/decode round-trip" $ do
      let instr = FLW fa0 x5 (Imm12 16)
      decode (encode instr) @?= Right instr

  , testCase "FCVT_W_S funct7=0x60 rs2-field=0" $ do
      let w = encode (FCVT_W_S x1 fa0 RNE)
      ((w `shiftR` 25) .&. 0x7F) @?= 0x60
      ((w `shiftR` 20) .&. 0x1F) @?= 0x00

  , testCase "FMV_X_W funct7=0x70 funct3=0x0" $ do
      let w = encode (FMV_X_W x1 fa0)
      ((w `shiftR` 25) .&. 0x7F) @?= 0x70
      ((w `shiftR` 12) .&. 0x7)  @?= 0x00
  ]
```

- [ ] **Step 2: Run to confirm compilation fails**

```bash
cabal test riscv-rig-test --test-options="--pattern=RV64F" 2>&1 | grep "error" | head -5
```

Expected: errors like `Variable not in scope: FLW`.

- [ ] **Step 3: Add FP constructors to `src/Core/Instruction.hs`**

Add after the RV64A section:

```haskell
  -- ── RV64F: Loads / Stores ───────────────────────────────────────
  | FLW   FPRegister Register Imm12      -- rd rs1 offset
  | FSW   FPRegister Register Imm12      -- rs2 rs1 offset (rs2=data, rs1=base)
  -- ── RV64F: Fused Multiply-Add (R4 format) ──────────────────────
  | FMADD_S  FPRegister FPRegister FPRegister FPRegister RoundingMode
  | FMSUB_S  FPRegister FPRegister FPRegister FPRegister RoundingMode
  | FNMADD_S FPRegister FPRegister FPRegister FPRegister RoundingMode
  | FNMSUB_S FPRegister FPRegister FPRegister FPRegister RoundingMode
  -- ── RV64F: 3-Operand (OP-FP) ───────────────────────────────────
  | FADD_S   FPRegister FPRegister FPRegister RoundingMode
  | FSUB_S   FPRegister FPRegister FPRegister RoundingMode
  | FMUL_S   FPRegister FPRegister FPRegister RoundingMode
  | FDIV_S   FPRegister FPRegister FPRegister RoundingMode
  | FSQRT_S  FPRegister FPRegister RoundingMode             -- 2 operand (rs2=0)
  | FSGNJ_S  FPRegister FPRegister FPRegister               -- sign inject
  | FSGNJN_S FPRegister FPRegister FPRegister
  | FSGNJX_S FPRegister FPRegister FPRegister
  | FMIN_S   FPRegister FPRegister FPRegister
  | FMAX_S   FPRegister FPRegister FPRegister
  -- ── RV64F: Conversions ─────────────────────────────────────────
  | FCVT_W_S  Register FPRegister RoundingMode   -- to int32
  | FCVT_WU_S Register FPRegister RoundingMode   -- to uint32
  | FCVT_L_S  Register FPRegister RoundingMode   -- to int64
  | FCVT_LU_S Register FPRegister RoundingMode   -- to uint64
  | FCVT_S_W  FPRegister Register RoundingMode   -- from int32
  | FCVT_S_WU FPRegister Register RoundingMode
  | FCVT_S_L  FPRegister Register RoundingMode   -- from int64
  | FCVT_S_LU FPRegister Register RoundingMode
  -- ── RV64F: Move / Compare / Classify ───────────────────────────
  | FMV_X_W   Register FPRegister              -- float bits to int
  | FMV_W_X   FPRegister Register              -- int bits to float
  | FEQ_S     Register FPRegister FPRegister
  | FLT_S     Register FPRegister FPRegister
  | FLE_S     Register FPRegister FPRegister
  | FCLASS_S  Register FPRegister
```

Update `instrExtension` (add all F constructors -> `RV64F`):

```haskell
  FLW{} -> RV64F; FSW{} -> RV64F
  FMADD_S{} -> RV64F; FMSUB_S{} -> RV64F; FNMADD_S{} -> RV64F; FNMSUB_S{} -> RV64F
  FADD_S{} -> RV64F; FSUB_S{} -> RV64F; FMUL_S{} -> RV64F; FDIV_S{} -> RV64F
  FSQRT_S{} -> RV64F; FSGNJ_S{} -> RV64F; FSGNJN_S{} -> RV64F; FSGNJX_S{} -> RV64F
  FMIN_S{} -> RV64F; FMAX_S{} -> RV64F
  FCVT_W_S{} -> RV64F; FCVT_WU_S{} -> RV64F; FCVT_L_S{} -> RV64F; FCVT_LU_S{} -> RV64F
  FCVT_S_W{} -> RV64F; FCVT_S_WU{} -> RV64F; FCVT_S_L{} -> RV64F; FCVT_S_LU{} -> RV64F
  FMV_X_W{} -> RV64F; FMV_W_X{} -> RV64F
  FEQ_S{} -> RV64F; FLT_S{} -> RV64F; FLE_S{} -> RV64F; FCLASS_S{} -> RV64F
```

Update `instrFormat` (FLW/FCVT_*/FMV_*/FEQ_*/FLT_*/FLE_*/FCLASS_*/FSQRT_* -> IFormat; FSW -> SFormat; FADD_*/... -> RFormat; FMADD_* -> R4 format use RFormat):

```haskell
  FLW{} -> IFormat; FSQRT_S{} -> RFormat
  FSW{} -> SFormat
  FMADD_S{} -> RFormat; FMSUB_S{} -> RFormat; FNMADD_S{} -> RFormat; FNMSUB_S{} -> RFormat
  FADD_S{} -> RFormat; FSUB_S{} -> RFormat; FMUL_S{} -> RFormat; FDIV_S{} -> RFormat
  FSGNJ_S{} -> RFormat; FSGNJN_S{} -> RFormat; FSGNJX_S{} -> RFormat
  FMIN_S{} -> RFormat; FMAX_S{} -> RFormat
  FCVT_W_S{} -> IFormat; FCVT_WU_S{} -> IFormat; FCVT_L_S{} -> IFormat; FCVT_LU_S{} -> IFormat
  FCVT_S_W{} -> RFormat; FCVT_S_WU{} -> RFormat; FCVT_S_L{} -> RFormat; FCVT_S_LU{} -> RFormat
  FMV_X_W{} -> RFormat; FMV_W_X{} -> RFormat
  FEQ_S{} -> RFormat; FLT_S{} -> RFormat; FLE_S{} -> RFormat; FCLASS_S{} -> RFormat
```

- [ ] **Step 4: Add FP encode helpers and cases to `src/Core/Encode.hs`**

Add helpers after `buildAMO`:

```haskell
fr :: FPRegister -> Word32
fr (FPRegister x) = fromIntegral x

encodeRM :: RoundingMode -> Word32
encodeRM RNE = 0; encodeRM RTZ = 1; encodeRM RDN = 2
encodeRM RUP = 3; encodeRM RMM = 4; encodeRM DYN = 7

-- Standard FP operation: opcode=0x53
buildFPOp :: Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32
buildFPOp funct7 rs2W rs1W rmW rdW =
  (funct7 `shiftL` 25) .|. (rs2W `shiftL` 20) .|. (rs1W `shiftL` 15)
  .|. (rmW `shiftL` 12) .|. (rdW `shiftL` 7) .|. 0x53

-- R4 format: FMADD/FMSUB/FNMADD/FNMSUB
buildR4 :: Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32
buildR4 opcode rs3W fmt rs2W rs1W rmW rdW =
  (rs3W `shiftL` 27) .|. (fmt `shiftL` 25) .|. (rs2W `shiftL` 20)
  .|. (rs1W `shiftL` 15) .|. (rmW `shiftL` 12) .|. (rdW `shiftL` 7) .|. opcode
```

Add encode cases to the `encode = \case` block:

```haskell
  -- ── RV64F ─────────────────────────────────────────────────────
  FLW  rd rs1 imm -> buildI 0x07 (fr rd) 0x2 (r rs1) (i12 imm)
  FSW  rs2 rs1 imm -> buildS 0x27 0x2 (r rs1) (fr rs2) (i12 imm)
  FMADD_S  rd rs1 rs2 rs3 rm -> buildR4 0x43 (fr rs3) 0x0 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FMSUB_S  rd rs1 rs2 rs3 rm -> buildR4 0x47 (fr rs3) 0x0 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FNMSUB_S rd rs1 rs2 rs3 rm -> buildR4 0x4B (fr rs3) 0x0 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FNMADD_S rd rs1 rs2 rs3 rm -> buildR4 0x4F (fr rs3) 0x0 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FADD_S  rd rs1 rs2 rm -> buildFPOp 0x00 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FSUB_S  rd rs1 rs2 rm -> buildFPOp 0x04 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FMUL_S  rd rs1 rs2 rm -> buildFPOp 0x08 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FDIV_S  rd rs1 rs2 rm -> buildFPOp 0x0C (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FSQRT_S rd rs1 rm     -> buildFPOp 0x2C 0          (fr rs1) (encodeRM rm) (fr rd)
  FSGNJ_S  rd rs1 rs2   -> buildFPOp 0x10 (fr rs2) (fr rs1) 0x0 (fr rd)
  FSGNJN_S rd rs1 rs2   -> buildFPOp 0x10 (fr rs2) (fr rs1) 0x1 (fr rd)
  FSGNJX_S rd rs1 rs2   -> buildFPOp 0x10 (fr rs2) (fr rs1) 0x2 (fr rd)
  FMIN_S   rd rs1 rs2   -> buildFPOp 0x14 (fr rs2) (fr rs1) 0x0 (fr rd)
  FMAX_S   rd rs1 rs2   -> buildFPOp 0x14 (fr rs2) (fr rs1) 0x1 (fr rd)
  FCVT_W_S  rd rs1 rm -> buildFPOp 0x60 0x00 (fr rs1) (encodeRM rm) (r rd)
  FCVT_WU_S rd rs1 rm -> buildFPOp 0x60 0x01 (fr rs1) (encodeRM rm) (r rd)
  FCVT_L_S  rd rs1 rm -> buildFPOp 0x60 0x02 (fr rs1) (encodeRM rm) (r rd)
  FCVT_LU_S rd rs1 rm -> buildFPOp 0x60 0x03 (fr rs1) (encodeRM rm) (r rd)
  FCVT_S_W  rd rs1 rm -> buildFPOp 0x68 0x00 (r rs1) (encodeRM rm) (fr rd)
  FCVT_S_WU rd rs1 rm -> buildFPOp 0x68 0x01 (r rs1) (encodeRM rm) (fr rd)
  FCVT_S_L  rd rs1 rm -> buildFPOp 0x68 0x02 (r rs1) (encodeRM rm) (fr rd)
  FCVT_S_LU rd rs1 rm -> buildFPOp 0x68 0x03 (r rs1) (encodeRM rm) (fr rd)
  FMV_X_W   rd rs1    -> buildFPOp 0x70 0x00 (fr rs1) 0x0 (r rd)
  FMV_W_X   rd rs1    -> buildFPOp 0x78 0x00 (r rs1) 0x0 (fr rd)
  FEQ_S     rd rs1 rs2 -> buildFPOp 0x50 (fr rs2) (fr rs1) 0x2 (r rd)
  FLT_S     rd rs1 rs2 -> buildFPOp 0x50 (fr rs2) (fr rs1) 0x1 (r rd)
  FLE_S     rd rs1 rs2 -> buildFPOp 0x50 (fr rs2) (fr rs1) 0x0 (r rd)
  FCLASS_S  rd rs1     -> buildFPOp 0x70 0x00 (fr rs1) 0x1 (r rd)
```

- [ ] **Step 5: Add FP decode to `src/Core/Decode.hs`**

Add to the `decode` dispatch:

```haskell
  0x07 -> decodeFPLoad w
  0x27 -> decodeFPStore w
  0x43 -> decodeFMAdd 0x43 0x0 w  -- FMADD_S
  0x47 -> decodeFMAdd 0x47 0x0 w  -- FMSUB_S
  0x4B -> decodeFMAdd 0x4B 0x0 w  -- FNMSUB_S
  0x4F -> decodeFMAdd 0x4F 0x0 w  -- FNMADD_S
  0x53 -> decodeFPOp w
```

Add helpers:

```haskell
mkFP :: Word32 -> FPRegister
mkFP = FPRegister . fromIntegral

decodeRM :: Word32 -> RoundingMode
decodeRM 0 = RNE; decodeRM 1 = RTZ; decodeRM 2 = RDN
decodeRM 3 = RUP; decodeRM 4 = RMM; _          = DYN

decodeFPLoad :: Word32 -> Either DecodeError Instruction
decodeFPLoad w = case funct3' w of
  0x2 -> Right $ FLW (mkFP (rd' w)) (mkReg (rs1' w)) (Imm12 (signExt12 w))
  0x3 -> Right $ FLD (mkFP (rd' w)) (mkReg (rs1' w)) (Imm12 (signExt12 w))
  f   -> Left  $ UnknownFunct3 0x07 f

decodeFPStore :: Word32 -> Either DecodeError Instruction
decodeFPStore w =
  let imm = Imm12 $ signExt12 $
              ((field w 31 25) `shiftL` 5) .|. (field w 11 7)
  in case funct3' w of
    0x2 -> Right $ FSW (mkFP (rs2' w)) (mkReg (rs1' w)) imm
    0x3 -> Right $ FSD (mkFP (rs2' w)) (mkReg (rs1' w)) imm
    f   -> Left  $ UnknownFunct3 0x27 f

decodeFMAdd :: Word32 -> Word32 -> Word32 -> Either DecodeError Instruction
decodeFMAdd opcode fmt w =
  let rd_  = mkFP (rd' w); rs1_ = mkFP (rs1' w)
      rs2_ = mkFP (rs2' w); rs3_ = mkFP (field w 31 27)
      rm_  = decodeRM (funct3' w)
      fmtW = field w 26 25
  in if fmtW /= fmt then Left (ReservedEncoding w)
     else case opcode of
       0x43 -> Right $ FMADD_S  rd_ rs1_ rs2_ rs3_ rm_
       0x47 -> Right $ FMSUB_S  rd_ rs1_ rs2_ rs3_ rm_
       0x4B -> Right $ FNMSUB_S rd_ rs1_ rs2_ rs3_ rm_
       0x4F -> Right $ FNMADD_S rd_ rs1_ rs2_ rs3_ rm_
       _    -> Left  $ UnknownOpcode opcode

decodeFPOp :: Word32 -> Either DecodeError Instruction
decodeFPOp w =
  let f7   = funct7' w; f3 = funct3' w
      rd_  = mkFP (rd' w); rdi  = mkReg (rd' w)
      rs1f = mkFP (rs1' w); rs1i = mkReg (rs1' w)
      rs2f = mkFP (rs2' w); rs2  = rs2' w
      rm   = decodeRM f3
  in case (f7, f3, rs2) of
    (0x00, _, _)  -> Right $ FADD_S  rd_ rs1f rs2f rm
    (0x04, _, _)  -> Right $ FSUB_S  rd_ rs1f rs2f rm
    (0x08, _, _)  -> Right $ FMUL_S  rd_ rs1f rs2f rm
    (0x0C, _, _)  -> Right $ FDIV_S  rd_ rs1f rs2f rm
    (0x2C, _, 0)  -> Right $ FSQRT_S rd_ rs1f rm
    (0x10, 0, _)  -> Right $ FSGNJ_S  rd_ rs1f rs2f
    (0x10, 1, _)  -> Right $ FSGNJN_S rd_ rs1f rs2f
    (0x10, 2, _)  -> Right $ FSGNJX_S rd_ rs1f rs2f
    (0x14, 0, _)  -> Right $ FMIN_S  rd_ rs1f rs2f
    (0x14, 1, _)  -> Right $ FMAX_S  rd_ rs1f rs2f
    (0x50, 2, _)  -> Right $ FEQ_S   rdi rs1f rs2f
    (0x50, 1, _)  -> Right $ FLT_S   rdi rs1f rs2f
    (0x50, 0, _)  -> Right $ FLE_S   rdi rs1f rs2f
    (0x60, _, 0)  -> Right $ FCVT_W_S  rdi rs1f rm
    (0x60, _, 1)  -> Right $ FCVT_WU_S rdi rs1f rm
    (0x60, _, 2)  -> Right $ FCVT_L_S  rdi rs1f rm
    (0x60, _, 3)  -> Right $ FCVT_LU_S rdi rs1f rm
    (0x68, _, 0)  -> Right $ FCVT_S_W  rd_ rs1i rm
    (0x68, _, 1)  -> Right $ FCVT_S_WU rd_ rs1i rm
    (0x68, _, 2)  -> Right $ FCVT_S_L  rd_ rs1i rm
    (0x68, _, 3)  -> Right $ FCVT_S_LU rd_ rs1i rm
    (0x70, 0, 0)  -> Right $ FMV_X_W   rdi rs1f
    (0x70, 1, 0)  -> Right $ FCLASS_S  rdi rs1f
    (0x78, 0, 0)  -> Right $ FMV_W_X   rd_ rs1i
    _             -> Left  $ UnknownFunct7 0x53 f3 f7
```

Note: `FLD`, `FSD`, `FADD_D` etc. will be added in Task 4. The `decodeFPLoad` handles `0x3 -> FLD` and `decodeFPStore` handles `0x3 -> FSD` – those constructors are added in Task 4. Leave them stubbed as `Left (ReservedEncoding w)` for now if you prefer, but adding the decode cases now (even before Task 4 adds the constructors) will cause compile errors. **Solution:** Add Task 4 constructors first, then come back to finish `decodeFPLoad`/`decodeFPStore` for D variants. Alternatively, add both F and D constructors in Task 3. For simplicity, add only the constructors used in the pattern match (FLD/FSD are referenced in decode helpers here so must be added in Task 3 or Task 4). If you encounter compile errors about FLD/FSD, add stub constructors now and fill encode/decode in Task 4.

- [ ] **Step 6: Run tests**

```bash
cabal test riscv-rig-test --test-options="--pattern=RV64F" 2>&1 | tail -10
```

Expected: All RV64F+D tests pass (FLD/FSD tests will fail until Task 4 if you haven't added them yet).

- [ ] **Step 7: Commit**

```bash
git add src/Core/Instruction.hs src/Core/Encode.hs src/Core/Decode.hs test/Test/Core/FloatInstr.hs
git commit -m "feat: add RV64F single-precision float instructions with encode/decode"
```

---

### Task 4: RV64D — Double-Precision Float Instructions

**Files:**
- Modify: `src/Core/Instruction.hs`
- Modify: `src/Core/Encode.hs`
- Modify: `src/Core/Decode.hs`

**Context:** D instructions are structurally identical to F but use `funct7` bit 0 = 1 (i.e., `funct7` values are F's +1 for most ops). `FLD`/`FSD` use `funct3=011` (F uses `010`). The R4 format uses `fmt=01` instead of `00`. FCVT between S and D uses special funct7 values. `FMV_X_D`/`FMV_D_X` replace `FMV_X_W`/`FMV_W_X` for 64-bit moves.

- [ ] **Step 1: Add D constructors to `src/Core/Instruction.hs`**

Add after the RV64F section:

```haskell
  -- ── RV64D: Loads / Stores ───────────────────────────────────────
  | FLD   FPRegister Register Imm12
  | FSD   FPRegister Register Imm12
  -- ── RV64D: Fused Multiply-Add ──────────────────────────────────
  | FMADD_D  FPRegister FPRegister FPRegister FPRegister RoundingMode
  | FMSUB_D  FPRegister FPRegister FPRegister FPRegister RoundingMode
  | FNMADD_D FPRegister FPRegister FPRegister FPRegister RoundingMode
  | FNMSUB_D FPRegister FPRegister FPRegister FPRegister RoundingMode
  -- ── RV64D: 3-Operand ───────────────────────────────────────────
  | FADD_D   FPRegister FPRegister FPRegister RoundingMode
  | FSUB_D   FPRegister FPRegister FPRegister RoundingMode
  | FMUL_D   FPRegister FPRegister FPRegister RoundingMode
  | FDIV_D   FPRegister FPRegister FPRegister RoundingMode
  | FSQRT_D  FPRegister FPRegister RoundingMode
  | FSGNJ_D  FPRegister FPRegister FPRegister
  | FSGNJN_D FPRegister FPRegister FPRegister
  | FSGNJX_D FPRegister FPRegister FPRegister
  | FMIN_D   FPRegister FPRegister FPRegister
  | FMAX_D   FPRegister FPRegister FPRegister
  -- ── RV64D: Conversions ─────────────────────────────────────────
  | FCVT_S_D FPRegister FPRegister RoundingMode  -- double→single
  | FCVT_D_S FPRegister FPRegister RoundingMode  -- single→double
  | FCVT_W_D  Register FPRegister RoundingMode
  | FCVT_WU_D Register FPRegister RoundingMode
  | FCVT_L_D  Register FPRegister RoundingMode
  | FCVT_LU_D Register FPRegister RoundingMode
  | FCVT_D_W  FPRegister Register RoundingMode
  | FCVT_D_WU FPRegister Register RoundingMode
  | FCVT_D_L  FPRegister Register RoundingMode
  | FCVT_D_LU FPRegister Register RoundingMode
  -- ── RV64D: Move / Compare / Classify ───────────────────────────
  | FMV_X_D   Register FPRegister
  | FMV_D_X   FPRegister Register
  | FEQ_D     Register FPRegister FPRegister
  | FLT_D     Register FPRegister FPRegister
  | FLE_D     Register FPRegister FPRegister
  | FCLASS_D  Register FPRegister
```

Update `instrExtension` (all D -> `RV64D`):

```haskell
  FLD{} -> RV64D; FSD{} -> RV64D
  FMADD_D{} -> RV64D; FMSUB_D{} -> RV64D; FNMADD_D{} -> RV64D; FNMSUB_D{} -> RV64D
  FADD_D{} -> RV64D; FSUB_D{} -> RV64D; FMUL_D{} -> RV64D; FDIV_D{} -> RV64D
  FSQRT_D{} -> RV64D; FSGNJ_D{} -> RV64D; FSGNJN_D{} -> RV64D; FSGNJX_D{} -> RV64D
  FMIN_D{} -> RV64D; FMAX_D{} -> RV64D
  FCVT_S_D{} -> RV64D; FCVT_D_S{} -> RV64D
  FCVT_W_D{} -> RV64D; FCVT_WU_D{} -> RV64D; FCVT_L_D{} -> RV64D; FCVT_LU_D{} -> RV64D
  FCVT_D_W{} -> RV64D; FCVT_D_WU{} -> RV64D; FCVT_D_L{} -> RV64D; FCVT_D_LU{} -> RV64D
  FMV_X_D{} -> RV64D; FMV_D_X{} -> RV64D
  FEQ_D{} -> RV64D; FLT_D{} -> RV64D; FLE_D{} -> RV64D; FCLASS_D{} -> RV64D
```

Update `instrFormat` (same pattern as F: FLD→IFormat, FSD→SFormat, rest→RFormat):

```haskell
  FLD{} -> IFormat; FSD{} -> SFormat
  FMADD_D{} -> RFormat; FMSUB_D{} -> RFormat; FNMADD_D{} -> RFormat; FNMSUB_D{} -> RFormat
  FADD_D{} -> RFormat; FSUB_D{} -> RFormat; FMUL_D{} -> RFormat; FDIV_D{} -> RFormat
  FSQRT_D{} -> RFormat; FSGNJ_D{} -> RFormat; FSGNJN_D{} -> RFormat; FSGNJX_D{} -> RFormat
  FMIN_D{} -> RFormat; FMAX_D{} -> RFormat
  FCVT_S_D{} -> RFormat; FCVT_D_S{} -> RFormat
  FCVT_W_D{} -> IFormat; FCVT_WU_D{} -> IFormat; FCVT_L_D{} -> IFormat; FCVT_LU_D{} -> IFormat
  FCVT_D_W{} -> RFormat; FCVT_D_WU{} -> RFormat; FCVT_D_L{} -> RFormat; FCVT_D_LU{} -> RFormat
  FMV_X_D{} -> RFormat; FMV_D_X{} -> RFormat
  FEQ_D{} -> RFormat; FLT_D{} -> RFormat; FLE_D{} -> RFormat; FCLASS_D{} -> RFormat
```

- [ ] **Step 2: Add D encode cases to `src/Core/Encode.hs`**

Add after the F cases:

```haskell
  -- ── RV64D ─────────────────────────────────────────────────────
  FLD  rd rs1 imm -> buildI 0x07 (fr rd) 0x3 (r rs1) (i12 imm)
  FSD  rs2 rs1 imm -> buildS 0x27 0x3 (r rs1) (fr rs2) (i12 imm)
  FMADD_D  rd rs1 rs2 rs3 rm -> buildR4 0x43 (fr rs3) 0x1 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FMSUB_D  rd rs1 rs2 rs3 rm -> buildR4 0x47 (fr rs3) 0x1 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FNMSUB_D rd rs1 rs2 rs3 rm -> buildR4 0x4B (fr rs3) 0x1 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FNMADD_D rd rs1 rs2 rs3 rm -> buildR4 0x4F (fr rs3) 0x1 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FADD_D  rd rs1 rs2 rm -> buildFPOp 0x01 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FSUB_D  rd rs1 rs2 rm -> buildFPOp 0x05 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FMUL_D  rd rs1 rs2 rm -> buildFPOp 0x09 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FDIV_D  rd rs1 rs2 rm -> buildFPOp 0x0D (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FSQRT_D rd rs1 rm     -> buildFPOp 0x2D 0          (fr rs1) (encodeRM rm) (fr rd)
  FSGNJ_D  rd rs1 rs2   -> buildFPOp 0x11 (fr rs2) (fr rs1) 0x0 (fr rd)
  FSGNJN_D rd rs1 rs2   -> buildFPOp 0x11 (fr rs2) (fr rs1) 0x1 (fr rd)
  FSGNJX_D rd rs1 rs2   -> buildFPOp 0x11 (fr rs2) (fr rs1) 0x2 (fr rd)
  FMIN_D   rd rs1 rs2   -> buildFPOp 0x15 (fr rs2) (fr rs1) 0x0 (fr rd)
  FMAX_D   rd rs1 rs2   -> buildFPOp 0x15 (fr rs2) (fr rs1) 0x1 (fr rd)
  FCVT_S_D rd rs1 rm -> buildFPOp 0x20 0x01 (fr rs1) (encodeRM rm) (fr rd)
  FCVT_D_S rd rs1 rm -> buildFPOp 0x21 0x00 (fr rs1) (encodeRM rm) (fr rd)
  FCVT_W_D  rd rs1 rm -> buildFPOp 0x61 0x00 (fr rs1) (encodeRM rm) (r rd)
  FCVT_WU_D rd rs1 rm -> buildFPOp 0x61 0x01 (fr rs1) (encodeRM rm) (r rd)
  FCVT_L_D  rd rs1 rm -> buildFPOp 0x61 0x02 (fr rs1) (encodeRM rm) (r rd)
  FCVT_LU_D rd rs1 rm -> buildFPOp 0x61 0x03 (fr rs1) (encodeRM rm) (r rd)
  FCVT_D_W  rd rs1 rm -> buildFPOp 0x69 0x00 (r rs1) (encodeRM rm) (fr rd)
  FCVT_D_WU rd rs1 rm -> buildFPOp 0x69 0x01 (r rs1) (encodeRM rm) (fr rd)
  FCVT_D_L  rd rs1 rm -> buildFPOp 0x69 0x02 (r rs1) (encodeRM rm) (fr rd)
  FCVT_D_LU rd rs1 rm -> buildFPOp 0x69 0x03 (r rs1) (encodeRM rm) (fr rd)
  FMV_X_D   rd rs1    -> buildFPOp 0x71 0x00 (fr rs1) 0x0 (r rd)
  FMV_D_X   rd rs1    -> buildFPOp 0x79 0x00 (r rs1) 0x0 (fr rd)
  FEQ_D     rd rs1 rs2 -> buildFPOp 0x51 (fr rs2) (fr rs1) 0x2 (r rd)
  FLT_D     rd rs1 rs2 -> buildFPOp 0x51 (fr rs2) (fr rs1) 0x1 (r rd)
  FLE_D     rd rs1 rs2 -> buildFPOp 0x51 (fr rs2) (fr rs1) 0x0 (r rd)
  FCLASS_D  rd rs1     -> buildFPOp 0x71 0x00 (fr rs1) 0x1 (r rd)
```

- [ ] **Step 3: Complete FP decode for D variants in `src/Core/Decode.hs`**

In `decodeFPLoad`, the `0x3` case already references `FLD` — now that the constructor exists, it compiles. Similarly `FSD` in `decodeFPStore`.

Add D variants to `decodeFPOp`:

```haskell
    (0x01, _, _)  -> Right $ FADD_D  rd_ rs1f rs2f rm
    (0x05, _, _)  -> Right $ FSUB_D  rd_ rs1f rs2f rm
    (0x09, _, _)  -> Right $ FMUL_D  rd_ rs1f rs2f rm
    (0x0D, _, _)  -> Right $ FDIV_D  rd_ rs1f rs2f rm
    (0x2D, _, 0)  -> Right $ FSQRT_D rd_ rs1f rm
    (0x11, 0, _)  -> Right $ FSGNJ_D  rd_ rs1f rs2f
    (0x11, 1, _)  -> Right $ FSGNJN_D rd_ rs1f rs2f
    (0x11, 2, _)  -> Right $ FSGNJX_D rd_ rs1f rs2f
    (0x15, 0, _)  -> Right $ FMIN_D  rd_ rs1f rs2f
    (0x15, 1, _)  -> Right $ FMAX_D  rd_ rs1f rs2f
    (0x20, _, 1)  -> Right $ FCVT_S_D rd_ rs1f rm
    (0x21, _, 0)  -> Right $ FCVT_D_S rd_ rs1f rm
    (0x51, 2, _)  -> Right $ FEQ_D   rdi rs1f rs2f
    (0x51, 1, _)  -> Right $ FLT_D   rdi rs1f rs2f
    (0x51, 0, _)  -> Right $ FLE_D   rdi rs1f rs2f
    (0x61, _, 0)  -> Right $ FCVT_W_D  rdi rs1f rm
    (0x61, _, 1)  -> Right $ FCVT_WU_D rdi rs1f rm
    (0x61, _, 2)  -> Right $ FCVT_L_D  rdi rs1f rm
    (0x61, _, 3)  -> Right $ FCVT_LU_D rdi rs1f rm
    (0x69, _, 0)  -> Right $ FCVT_D_W  rd_ rs1i rm
    (0x69, _, 1)  -> Right $ FCVT_D_WU rd_ rs1i rm
    (0x69, _, 2)  -> Right $ FCVT_D_L  rd_ rs1i rm
    (0x69, _, 3)  -> Right $ FCVT_D_LU rd_ rs1i rm
    (0x71, 0, 0)  -> Right $ FMV_X_D   rdi rs1f
    (0x71, 1, 0)  -> Right $ FCLASS_D  rdi rs1f
    (0x79, 0, 0)  -> Right $ FMV_D_X   rd_ rs1i
```

Also add FMADD_D/FMSUB_D/FNMADD_D/FNMSUB_D to `decodeFMAdd`: update it to dispatch on `fmtW`:

```haskell
decodeFMAdd :: Word32 -> Word32 -> Either DecodeError Instruction
decodeFMAdd opcode w =
  let rd_  = mkFP (rd' w); rs1_ = mkFP (rs1' w)
      rs2_ = mkFP (rs2' w); rs3_ = mkFP (field w 31 27)
      rm_  = decodeRM (funct3' w)
      fmt  = field w 26 25
  in case (opcode, fmt) of
    (0x43, 0) -> Right $ FMADD_S  rd_ rs1_ rs2_ rs3_ rm_
    (0x47, 0) -> Right $ FMSUB_S  rd_ rs1_ rs2_ rs3_ rm_
    (0x4B, 0) -> Right $ FNMSUB_S rd_ rs1_ rs2_ rs3_ rm_
    (0x4F, 0) -> Right $ FNMADD_S rd_ rs1_ rs2_ rs3_ rm_
    (0x43, 1) -> Right $ FMADD_D  rd_ rs1_ rs2_ rs3_ rm_
    (0x47, 1) -> Right $ FMSUB_D  rd_ rs1_ rs2_ rs3_ rm_
    (0x4B, 1) -> Right $ FNMSUB_D rd_ rs1_ rs2_ rs3_ rm_
    (0x4F, 1) -> Right $ FNMADD_D rd_ rs1_ rs2_ rs3_ rm_
    _         -> Left  $ ReservedEncoding w
```

Update the `decode` dispatch to call `decodeFMAdd opcode w` (drop the second arg, it now extracts fmt internally):
```haskell
  0x43 -> decodeFMAdd 0x43 w
  0x47 -> decodeFMAdd 0x47 w
  0x4B -> decodeFMAdd 0x4B  w
  0x4F -> decodeFMAdd 0x4F w
```

- [ ] **Step 4: Run all float tests**

```bash
cabal test riscv-rig-test --test-options="--pattern=RV64F" 2>&1 | tail -10
```

Expected: All RV64F+D tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/Core/Instruction.hs src/Core/Encode.hs src/Core/Decode.hs
git commit -m "feat: add RV64D double-precision float instructions with encode/decode"
```

---

### Task 5: RV64C — Compressed Instructions

**Files:**
- Modify: `src/Core/Instruction.hs`
- Modify: `src/Core/Encode.hs` (add `encode16 :: Instruction -> Word16`)
- Modify: `src/Core/Decode.hs` (add `decode16 :: Word16 -> Either DecodeError Instruction`)
- Create: `test/Test/Core/Compressed.hs`

**Context:** Compressed instructions use 16-bit encoding. They are added to the same `Instruction` ADT but with `C_` prefix. The new types `UImm7`, `UImm8`, `UImm9`, `UImm10`, `Imm9`, `Imm10` from Task 1 are used here. Compressed registers x8-x15 are encoded as 3-bit fields (0→x8, 7→x15).

- [ ] **Step 1: Write failing tests in `test/Test/Core/Compressed.hs`**

```haskell
module Test.Core.Compressed (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Core.Types
import Core.Instruction
import Core.Encode  (encode16)
import Core.Decode  (decode16)
import Data.Bits    (shiftR, (.&.))

tests :: TestTree
tests = testGroup "RV64C"
  [ testCase "C_ADDI quadrant=01" $ do
      let w = encode16 (C_ADDI x1 (Imm6 1))
      (w .&. 0x3) @?= 0x1

  , testCase "C_ADDI funct3=000" $ do
      let w = encode16 (C_ADDI x1 (Imm6 1))
      ((w `shiftR` 13) .&. 0x7) @?= 0x0

  , testCase "C_LW quadrant=00 funct3=010" $ do
      let w = encode16 (C_LW x8 x9 (UImm7 0))
      (w .&. 0x3) @?= 0x0
      ((w `shiftR` 13) .&. 0x7) @?= 0x2

  , testCase "C_J quadrant=01 funct3=101" $ do
      let w = encode16 (C_J (Imm12 0))
      (w .&. 0x3) @?= 0x1
      ((w `shiftR` 13) .&. 0x7) @?= 0x5

  , testCase "C_MV quadrant=10 funct4=1000" $ do
      let w = encode16 (C_MV x1 x2)
      (w .&. 0x3) @?= 0x2
      ((w `shiftR` 12) .&. 0xF) @?= 0x8

  , testCase "C_ADDI encode/decode round-trip" $ do
      let instr = C_ADDI x5 (Imm6 (-3))
      decode16 (encode16 instr) @?= Right instr

  , testCase "C_LD encode/decode round-trip" $ do
      let instr = C_LD x8 x9 (UImm8 16)
      decode16 (encode16 instr) @?= Right instr

  , testCase "C_BEQZ encode/decode round-trip" $ do
      let instr = C_BEQZ x8 (Imm9 4)
      decode16 (encode16 instr) @?= Right instr
  ]
```

- [ ] **Step 2: Run to confirm fails**

```bash
cabal test riscv-rig-test --test-options="--pattern=RV64C" 2>&1 | grep "error" | head -5
```

Expected: errors like `Variable not in scope: C_ADDI`.

- [ ] **Step 3: Add RV64C constructors to `src/Core/Instruction.hs`**

Add after the RV64D section:

```haskell
  -- ── RV64C: Quadrant 00 ─────────────────────────────────────────
  | C_ADDI4SPN Register UImm10    -- rd' = x8-x15, nzuimm (byte offset)
  | C_LW  Register Register UImm7 -- rd' rs1' offset (offset = unUImm7*4)
  | C_LD  Register Register UImm8 -- rd' rs1' offset (offset = unUImm8*8)
  | C_SW  Register Register UImm7 -- rs1' rs2' offset
  | C_SD  Register Register UImm8 -- rs1' rs2' offset
  -- ── RV64C: Quadrant 01 ─────────────────────────────────────────
  | C_ADDI   Register Imm6         -- rd (≠0), nzimm
  | C_ADDIW  Register Imm6         -- rd (≠0), imm (RV64 only)
  | C_LI     Register Imm6         -- rd, imm
  | C_ADDI16SP Imm10               -- sp += imm*16
  | C_LUI    Register Imm6         -- rd (≠x0,x2), nzimm18 (= Imm6 << 12)
  | C_SRLI   Register UImm6        -- rd' (x8-x15)
  | C_SRAI   Register UImm6
  | C_ANDI   Register Imm6
  | C_SUB    Register Register      -- rd' rs2' (rd -= rs2)
  | C_XOR    Register Register
  | C_OR     Register Register
  | C_AND    Register Register
  | C_SUBW   Register Register      -- rd' rs2' (RV64 only)
  | C_ADDW   Register Register
  | C_J      Imm12                  -- offset (≤ ±1KB)
  | C_BEQZ   Register Imm9          -- rs1' (x8-x15), offset
  | C_BNEZ   Register Imm9
  -- ── RV64C: Quadrant 10 ─────────────────────────────────────────
  | C_SLLI   Register UImm6         -- rd (≠0)
  | C_LWSP   Register UImm8         -- rd (≠0), offset (= unUImm8*4)
  | C_LDSP   Register UImm9         -- rd (≠0), offset (= unUImm9*8)
  | C_JR     Register               -- rs1 (≠0): jalr x0, rs1, 0
  | C_MV     Register Register      -- rd, rs2 (≠0): add rd, x0, rs2
  | C_EBREAK                        -- ebreak (compressed)
  | C_JALR   Register               -- rs1 (≠0): jalr ra, rs1, 0
  | C_ADD    Register Register       -- rd (≠0), rs2 (≠0): add rd, rd, rs2
  | C_SWSP   Register UImm8         -- rs2, offset (= unUImm8*4)
  | C_SDSP   Register UImm9         -- rs2, offset (= unUImm9*8)
```

Update `instrExtension` (all C_ -> `RV64C`):

```haskell
  C_ADDI4SPN{} -> RV64C; C_LW{} -> RV64C; C_LD{} -> RV64C
  C_SW{} -> RV64C; C_SD{} -> RV64C
  C_ADDI{} -> RV64C; C_ADDIW{} -> RV64C; C_LI{} -> RV64C
  C_ADDI16SP{} -> RV64C; C_LUI{} -> RV64C
  C_SRLI{} -> RV64C; C_SRAI{} -> RV64C; C_ANDI{} -> RV64C
  C_SUB{} -> RV64C; C_XOR{} -> RV64C; C_OR{} -> RV64C; C_AND{} -> RV64C
  C_SUBW{} -> RV64C; C_ADDW{} -> RV64C
  C_J{} -> RV64C; C_BEQZ{} -> RV64C; C_BNEZ{} -> RV64C
  C_SLLI{} -> RV64C; C_LWSP{} -> RV64C; C_LDSP{} -> RV64C
  C_JR{} -> RV64C; C_MV{} -> RV64C; C_EBREAK -> RV64C
  C_JALR{} -> RV64C; C_ADD{} -> RV64C
  C_SWSP{} -> RV64C; C_SDSP{} -> RV64C
```

Update `instrFormat` (all C_ -> `IFormat` as a placeholder — RVC doesn't fit any standard 32-bit format):

```haskell
  C_ADDI4SPN{} -> IFormat; C_LW{} -> IFormat; C_LD{} -> IFormat
  -- ... all C_ -> IFormat
  C_SDSP{} -> IFormat
```

- [ ] **Step 4: Add `encode16` to `src/Core/Encode.hs`**

Add these helpers and the function:

```haskell
-- 3-bit compressed register encoding: x8→0, x9→1, ..., x15→7
cr' :: Register -> Word16
cr' (Register x) = fromIntegral (x .&. 0x7)

-- Build a 16-bit compressed instruction
-- Helpers for common RVC formats:

buildCIW :: Word16 -> Word16 -> Word16 -> Word16
buildCIW funct3 nzuimm rd3 =
  (funct3 `shiftL` 13) .|. (nzuimm `shiftL` 5) .|. (rd3 `shiftL` 2) .|. 0x0

buildCL :: Word16 -> Word16 -> Word16 -> Word16 -> Word16
buildCL funct3 uimm rs1' rd' =
  (funct3 `shiftL` 13) .|. ((uimm .&. 0x38) `shiftL` 7)
  .|. (rs1' `shiftL` 7) .|. ((uimm .&. 0x4) `shiftL` 4)
  -- Note: actual bit placement differs per instruction; simplified here
  -- Use the exact bit-field layout per RVC spec
  .|. (rd' `shiftL` 2) .|. 0x0

buildCS :: Word16 -> Word16 -> Word16 -> Word16 -> Word16
buildCS funct3 uimm rs1' rs2' =
  (funct3 `shiftL` 13) .|. ((uimm .&. 0x38) `shiftL` 7)
  .|. (rs1' `shiftL` 7) .|. ((uimm .&. 0x4) `shiftL` 4)
  .|. (rs2' `shiftL` 2) .|. 0x0

buildCI :: Word16 -> Word16 -> Word16 -> Word16 -> Word16
buildCI funct3 imm5 rdrs1 imm4_0 =
  (funct3 `shiftL` 13) .|. (imm5 `shiftL` 12)
  .|. (rdrs1 `shiftL` 7) .|. (imm4_0 `shiftL` 2) .|. 0x1

buildCJ :: Word16 -> Word16 -> Word16
buildCJ funct3 target =
  let t = target .&. 0x7FF
      -- RVC J-type bit scrambling: j[11]|j[4]|j[9:8]|j[10]|j[6]|j[7]|j[3:1]|j[5]
      b11 = (t `shiftR` 10) .&. 0x1
      b4  = (t `shiftR` 4)  .&. 0x1
      b9  = (t `shiftR` 9)  .&. 0x1
      b8  = (t `shiftR` 8)  .&. 0x1
      b10 = (t `shiftR` 10) .&. 0x1
      b6  = (t `shiftR` 6)  .&. 0x1
      b7  = (t `shiftR` 7)  .&. 0x1
      b3  = (t `shiftR` 3)  .&. 0x1
      b2  = (t `shiftR` 2)  .&. 0x1
      b1  = (t `shiftR` 1)  .&. 0x1
      b5  = (t `shiftR` 5)  .&. 0x1
      bits = (b11 `shiftL` 11) .|. (b4 `shiftL` 10) .|. (b9 `shiftL` 9)
           .|. (b8 `shiftL` 8) .|. (b10 `shiftL` 7) .|. (b6 `shiftL` 6)
           .|. (b7 `shiftL` 5) .|. (b3 `shiftL` 4)  .|. (b2 `shiftL` 3)
           .|. (b1 `shiftL` 2) .|. (b5 `shiftL` 1)
  in (funct3 `shiftL` 13) .|. (bits `shiftL` 2) .|. 0x1

splitImm6 :: Int8 -> (Word16, Word16)  -- (bit5, bits4:0)
splitImm6 v =
  let w = fromIntegral v .&. 0x3F :: Word16
  in (w `shiftR` 5, w .&. 0x1F)

encode16 :: Instruction -> Word16
encode16 = \case
  -- Quadrant 00
  C_ADDI4SPN rd nzuimm ->
    -- nzuimm[5:4|9:6|2|3] packed into bits 12:5
    let v = fromIntegral (unUImm10 nzuimm) :: Word16
        bits = ((v `shiftR` 4) .&. 0x3) `shiftL` 11    -- nzuimm[5:4] -> [12:11]
             .|. ((v `shiftR` 6) .&. 0xF) `shiftL` 7   -- nzuimm[9:6] -> [10:7]
             .|. ((v `shiftR` 2) .&. 0x1) `shiftL` 6   -- nzuimm[2] -> [6]
             .|. ((v `shiftR` 3) .&. 0x1) `shiftL` 5   -- nzuimm[3] -> [5]
    in (0x0 `shiftL` 13) .|. bits .|. (cr' rd `shiftL` 2) .|. 0x0

  C_LW rd rs1 uimm7 ->
    -- uimm[5:3|2|6] (word load)
    let v = fromIntegral (unUImm7 uimm7) :: Word16
        bits = ((v `shiftR` 3) .&. 0x7) `shiftL` 10   -- [5:3] -> [12:10]
             .|. ((v `shiftR` 6) .&. 0x1) `shiftL` 5  -- [6] -> [5]
             .|. ((v `shiftR` 2) .&. 0x1) `shiftL` 6  -- [2] -> [6]
    in (0x2 `shiftL` 13) .|. (cr' rs1 `shiftL` 7) .|. bits .|. (cr' rd `shiftL` 2) .|. 0x0

  C_LD rd rs1 uimm8 ->
    -- uimm[5:3|7:6] (double load)
    let v = fromIntegral (unUImm8 uimm8) :: Word16
        bits = ((v `shiftR` 3) .&. 0x7) `shiftL` 10   -- [5:3] -> [12:10]
             .|. ((v `shiftR` 6) .&. 0x3) `shiftL` 5  -- [7:6] -> [6:5]
    in (0x3 `shiftL` 13) .|. (cr' rs1 `shiftL` 7) .|. bits .|. (cr' rd `shiftL` 2) .|. 0x0

  C_SW rs1 rs2 uimm7 ->
    let v = fromIntegral (unUImm7 uimm7) :: Word16
        bits = ((v `shiftR` 3) .&. 0x7) `shiftL` 10
             .|. ((v `shiftR` 6) .&. 0x1) `shiftL` 5
             .|. ((v `shiftR` 2) .&. 0x1) `shiftL` 6
    in (0x6 `shiftL` 13) .|. (cr' rs1 `shiftL` 7) .|. bits .|. (cr' rs2 `shiftL` 2) .|. 0x0

  C_SD rs1 rs2 uimm8 ->
    let v = fromIntegral (unUImm8 uimm8) :: Word16
        bits = ((v `shiftR` 3) .&. 0x7) `shiftL` 10
             .|. ((v `shiftR` 6) .&. 0x3) `shiftL` 5
    in (0x7 `shiftL` 13) .|. (cr' rs1 `shiftL` 7) .|. bits .|. (cr' rs2 `shiftL` 2) .|. 0x0

  -- Quadrant 01
  C_ADDI rd imm6 ->
    let (b5, b4_0) = splitImm6 (fromIntegral (unImm6 imm6))
    in (0x0 `shiftL` 13) .|. (b5 `shiftL` 12) .|. (fromIntegral (unReg rd) `shiftL` 7)
       .|. (b4_0 `shiftL` 2) .|. 0x1

  C_ADDIW rd imm6 ->
    let (b5, b4_0) = splitImm6 (fromIntegral (unImm6 imm6))
    in (0x1 `shiftL` 13) .|. (b5 `shiftL` 12) .|. (fromIntegral (unReg rd) `shiftL` 7)
       .|. (b4_0 `shiftL` 2) .|. 0x1

  C_LI rd imm6 ->
    let (b5, b4_0) = splitImm6 (fromIntegral (unImm6 imm6))
    in (0x2 `shiftL` 13) .|. (b5 `shiftL` 12) .|. (fromIntegral (unReg rd) `shiftL` 7)
       .|. (b4_0 `shiftL` 2) .|. 0x1

  C_ADDI16SP imm10 ->
    -- nzimm[9|4|6|8:7|5] packed into imm fields, rd=sp=x2
    let v = fromIntegral (unImm10 imm10) :: Word16
        b9 = (v `shiftR` 9) .&. 0x1
        b4 = (v `shiftR` 4) .&. 0x1
        b6 = (v `shiftR` 6) .&. 0x1
        b8 = (v `shiftR` 8) .&. 0x1
        b7 = (v `shiftR` 7) .&. 0x1
        b5 = (v `shiftR` 5) .&. 0x1
        bits = (b4 `shiftL` 4) .|. (b6 `shiftL` 3) .|. (b8 `shiftL` 2)
             .|. (b7 `shiftL` 1) .|. b5
    in (0x3 `shiftL` 13) .|. (b9 `shiftL` 12) .|. (0x2 `shiftL` 7)
       .|. (bits `shiftL` 2) .|. 0x1

  C_LUI rd imm6 ->
    let (b5, b4_0) = splitImm6 (fromIntegral (unImm6 imm6))
    in (0x3 `shiftL` 13) .|. (b5 `shiftL` 12) .|. (fromIntegral (unReg rd) `shiftL` 7)
       .|. (b4_0 `shiftL` 2) .|. 0x1

  C_SRLI rd uimm6 ->
    let v = fromIntegral (unUImm6 uimm6) :: Word16
    in (0x4 `shiftL` 13) .|. ((v `shiftR` 5) `shiftL` 12)
       .|. (0x0 `shiftL` 10) .|. (cr' rd `shiftL` 7)
       .|. ((v .&. 0x1F) `shiftL` 2) .|. 0x1

  C_SRAI rd uimm6 ->
    let v = fromIntegral (unUImm6 uimm6) :: Word16
    in (0x4 `shiftL` 13) .|. ((v `shiftR` 5) `shiftL` 12)
       .|. (0x1 `shiftL` 10) .|. (cr' rd `shiftL` 7)
       .|. ((v .&. 0x1F) `shiftL` 2) .|. 0x1

  C_ANDI rd imm6 ->
    let (b5, b4_0) = splitImm6 (fromIntegral (unImm6 imm6))
    in (0x4 `shiftL` 13) .|. (b5 `shiftL` 12) .|. (0x2 `shiftL` 10)
       .|. (cr' rd `shiftL` 7) .|. (b4_0 `shiftL` 2) .|. 0x1

  C_SUB  rd rs2 -> (0x4 `shiftL` 13).|.(0x3`shiftL`10).|.(cr' rd`shiftL`7).|.(0x0`shiftL`5).|.(cr' rs2`shiftL`2).|.0x1
  C_XOR  rd rs2 -> (0x4 `shiftL` 13).|.(0x3`shiftL`10).|.(cr' rd`shiftL`7).|.(0x1`shiftL`5).|.(cr' rs2`shiftL`2).|.0x1
  C_OR   rd rs2 -> (0x4 `shiftL` 13).|.(0x3`shiftL`10).|.(cr' rd`shiftL`7).|.(0x2`shiftL`5).|.(cr' rs2`shiftL`2).|.0x1
  C_AND  rd rs2 -> (0x4 `shiftL` 13).|.(0x3`shiftL`10).|.(cr' rd`shiftL`7).|.(0x3`shiftL`5).|.(cr' rs2`shiftL`2).|.0x1
  C_SUBW rd rs2 -> (0x4 `shiftL` 13).|.(0x3`shiftL`10).|.(0x1`shiftL`12).|.(cr' rd`shiftL`7).|.(0x0`shiftL`5).|.(cr' rs2`shiftL`2).|.0x1
  C_ADDW rd rs2 -> (0x4 `shiftL` 13).|.(0x3`shiftL`10).|.(0x1`shiftL`12).|.(cr' rd`shiftL`7).|.(0x1`shiftL`5).|.(cr' rs2`shiftL`2).|.0x1

  C_J imm12 ->
    buildCJ 0x5 (fromIntegral (unImm12 imm12) .&. 0x7FF)

  C_BEQZ rs1 imm9 ->
    let v = fromIntegral (unImm9 imm9) :: Word16
        b8   = (v `shiftR` 8) .&. 0x1
        b4_3 = (v `shiftR` 3) .&. 0x3
        b7_6 = (v `shiftR` 6) .&. 0x3
        b2_1 = (v `shiftR` 1) .&. 0x3
        b5   = (v `shiftR` 5) .&. 0x1
    in (0x6 `shiftL` 13) .|. (b8 `shiftL` 12) .|. (b4_3 `shiftL` 10)
       .|. (cr' rs1 `shiftL` 7) .|. (b7_6 `shiftL` 5) .|. (b2_1 `shiftL` 3)
       .|. (b5 `shiftL` 2) .|. 0x1

  C_BNEZ rs1 imm9 ->
    let v = fromIntegral (unImm9 imm9) :: Word16
        b8   = (v `shiftR` 8) .&. 0x1
        b4_3 = (v `shiftR` 3) .&. 0x3
        b7_6 = (v `shiftR` 6) .&. 0x3
        b2_1 = (v `shiftR` 1) .&. 0x3
        b5   = (v `shiftR` 5) .&. 0x1
    in (0x7 `shiftL` 13) .|. (b8 `shiftL` 12) .|. (b4_3 `shiftL` 10)
       .|. (cr' rs1 `shiftL` 7) .|. (b7_6 `shiftL` 5) .|. (b2_1 `shiftL` 3)
       .|. (b5 `shiftL` 2) .|. 0x1

  -- Quadrant 10
  C_SLLI rd uimm6 ->
    let v = fromIntegral (unUImm6 uimm6) :: Word16
    in (0x0 `shiftL` 13) .|. ((v `shiftR` 5) `shiftL` 12)
       .|. (fromIntegral (unReg rd) `shiftL` 7) .|. ((v .&. 0x1F) `shiftL` 2) .|. 0x2

  C_LWSP rd uimm8 ->
    let v = fromIntegral (unUImm8 uimm8) :: Word16
        -- offset[5]|rd|offset[4:2|7:6]
        b5   = (v `shiftR` 5) .&. 0x1
        b4_2 = (v `shiftR` 2) .&. 0x7
        b7_6 = (v `shiftR` 6) .&. 0x3
    in (0x2 `shiftL` 13) .|. (b5 `shiftL` 12)
       .|. (fromIntegral (unReg rd) `shiftL` 7)
       .|. (b4_2 `shiftL` 4) .|. (b7_6 `shiftL` 2) .|. 0x2

  C_LDSP rd uimm9 ->
    let v = fromIntegral (unUImm9 uimm9) :: Word16
        b5   = (v `shiftR` 5) .&. 0x1
        b4_3 = (v `shiftR` 3) .&. 0x3
        b8_6 = (v `shiftR` 6) .&. 0x7
    in (0x3 `shiftL` 13) .|. (b5 `shiftL` 12)
       .|. (fromIntegral (unReg rd) `shiftL` 7)
       .|. (b4_3 `shiftL` 5) .|. (b8_6 `shiftL` 2) .|. 0x2

  C_JR    rs1    -> (0x4 `shiftL` 13) .|. (0x0 `shiftL` 12)
                    .|. (fromIntegral (unReg rs1) `shiftL` 7) .|. 0x2

  C_MV    rd rs2 -> (0x4 `shiftL` 13) .|. (0x0 `shiftL` 12)
                    .|. (fromIntegral (unReg rd) `shiftL` 7)
                    .|. (fromIntegral (unReg rs2) `shiftL` 2) .|. 0x2

  C_EBREAK       -> (0x4 `shiftL` 13) .|. (0x1 `shiftL` 12) .|. 0x2

  C_JALR  rs1    -> (0x4 `shiftL` 13) .|. (0x1 `shiftL` 12)
                    .|. (fromIntegral (unReg rs1) `shiftL` 7) .|. 0x2

  C_ADD   rd rs2 -> (0x4 `shiftL` 13) .|. (0x1 `shiftL` 12)
                    .|. (fromIntegral (unReg rd) `shiftL` 7)
                    .|. (fromIntegral (unReg rs2) `shiftL` 2) .|. 0x2

  C_SWSP  rs2 uimm8 ->
    let v = fromIntegral (unUImm8 uimm8) :: Word16
        b5_2 = (v `shiftR` 2) .&. 0xF
        b7_6 = (v `shiftR` 6) .&. 0x3
    in (0x6 `shiftL` 13) .|. (b5_2 `shiftL` 9) .|. (b7_6 `shiftL` 7)
       .|. (fromIntegral (unReg rs2) `shiftL` 2) .|. 0x2

  C_SDSP  rs2 uimm9 ->
    let v = fromIntegral (unUImm9 uimm9) :: Word16
        b5_3 = (v `shiftR` 3) .&. 0x7
        b8_6 = (v `shiftR` 6) .&. 0x7
    in (0x7 `shiftL` 13) .|. (b5_3 `shiftL` 10) .|. (b8_6 `shiftL` 7)
       .|. (fromIntegral (unReg rs2) `shiftL` 2) .|. 0x2

  -- Non-compressed: this should not be called for 32-bit instructions
  -- but we need a total function
  other -> fromIntegral (encode other .&. 0xFFFF)
```

Update the module export line in `src/Core/Encode.hs` to export `encode16`:

```haskell
module Core.Encode (encode, encode16) where
```

Add `Data.Word (Word16)` to imports if not present.

- [ ] **Step 5: Add `decode16` to `src/Core/Decode.hs`**

Add to module exports: `decode16`.

```haskell
-- Helper: 3-bit compressed register field → Register
mkCReg :: Word16 -> Register
mkCReg x = Register (fromIntegral x + 8)  -- 0→x8, 7→x15

cField :: Word16 -> Int -> Int -> Word16
cField w hi lo = (w `shiftR` lo) .&. ((1 `shiftL` (hi - lo + 1)) - 1)

signExt6C :: Word16 -> Int8
signExt6C v =
  let raw = fromIntegral (v .&. 0x3F) :: Int8
  in if raw .&. 0x20 /= 0 then raw - 64 else raw

decode16 :: Word16 -> Either DecodeError Instruction
decode16 w =
  let quad   = w .&. 0x3
      funct3 = cField w 15 13
  in case quad of
    0x0 -> decodeQ0 w funct3
    0x1 -> decodeQ1 w funct3
    0x2 -> decodeQ2 w funct3
    _   -> Left (ReservedEncoding (fromIntegral w))

decodeQ0 :: Word16 -> Word16 -> Either DecodeError Instruction
decodeQ0 w funct3 =
  let rd'  = mkCReg (cField w 4 2)
      rs1' = mkCReg (cField w 9 7)
      rs2' = mkCReg (cField w 4 2)
  in case funct3 of
    0x0 ->  -- C.ADDI4SPN
      let nzuimm = (cField w 10 7 `shiftL` 6) .|. (cField w 12 11 `shiftL` 4)
                 .|. (cField w 5 5 `shiftL` 3) .|. (cField w 6 6 `shiftL` 2)
      in Right $ C_ADDI4SPN rd' (UImm10 nzuimm)
    0x2 ->  -- C.LW
      let uimm = (cField w 12 10 `shiftL` 3) .|. (cField w 6 6 `shiftL` 2)
               .|. (cField w 5 5 `shiftL` 6)
      in Right $ C_LW rd' rs1' (UImm7 (fromIntegral uimm))
    0x3 ->  -- C.LD
      let uimm = (cField w 12 10 `shiftL` 3) .|. (cField w 6 5 `shiftL` 6)
      in Right $ C_LD rd' rs1' (UImm8 (fromIntegral uimm))
    0x6 ->  -- C.SW
      let uimm = (cField w 12 10 `shiftL` 3) .|. (cField w 6 6 `shiftL` 2)
               .|. (cField w 5 5 `shiftL` 6)
      in Right $ C_SW rs1' rs2' (UImm7 (fromIntegral uimm))
    0x7 ->  -- C.SD
      let uimm = (cField w 12 10 `shiftL` 3) .|. (cField w 6 5 `shiftL` 6)
      in Right $ C_SD rs1' rs2' (UImm8 (fromIntegral uimm))
    f   -> Left (UnknownFunct3 0x0 (fromIntegral f))

decodeQ1 :: Word16 -> Word16 -> Either DecodeError Instruction
decodeQ1 w funct3 =
  let rdrs1 = Register (fromIntegral (cField w 11 7))
      rd'c  = mkCReg (cField w 9 7)
      rs2'c = mkCReg (cField w 4 2)
      imm6  = Imm6 $ signExt6C ((cField w 12 12 `shiftL` 5) .|. cField w 6 2)
  in case funct3 of
    0x0 -> Right $ C_ADDI rdrs1 imm6
    0x1 -> Right $ C_ADDIW rdrs1 imm6
    0x2 -> Right $ C_LI rdrs1 imm6
    0x3 ->
      let rd5 = cField w 11 7
      in if rd5 == 2
         then  -- C.ADDI16SP
           let nzimm = (cField w 12 12 `shiftL` 9) .|. (cField w 4 4 `shiftL` 4)
                     .|. (cField w 5 5 `shiftL` 6)  .|. (cField w 3 2 `shiftL` 7)
                     .|. (cField w 6 6 `shiftL` 5)
               v = fromIntegral (if nzimm .&. 0x200 /= 0 then nzimm - 0x400 else nzimm) :: Int16
           in Right $ C_ADDI16SP (Imm10 v)
         else  -- C.LUI
           Right $ C_LUI rdrs1 imm6
    0x4 ->
      let funct2 = cField w 11 10
          bit12  = cField w 12 12
      in case (funct2, bit12) of
        (0x0, _) -> Right $ C_SRLI rd'c (UImm6 (fromIntegral ((bit12 `shiftL` 5) .|. cField w 6 2)))
        (0x1, _) -> Right $ C_SRAI rd'c (UImm6 (fromIntegral ((bit12 `shiftL` 5) .|. cField w 6 2)))
        (0x2, _) -> Right $ C_ANDI rd'c (Imm6 $ signExt6C ((bit12 `shiftL` 5) .|. cField w 6 2))
        (0x3, 0) ->
          let rs2c = mkCReg (cField w 4 2)
              sub3 = cField w 6 5
          in case sub3 of
            0x0 -> Right $ C_SUB rd'c rs2c
            0x1 -> Right $ C_XOR rd'c rs2c
            0x2 -> Right $ C_OR  rd'c rs2c
            0x3 -> Right $ C_AND rd'c rs2c
            _   -> Left (ReservedEncoding (fromIntegral w))
        (0x3, 1) ->
          let rs2c = mkCReg (cField w 4 2)
              sub3 = cField w 6 5
          in case sub3 of
            0x0 -> Right $ C_SUBW rd'c rs2c
            0x1 -> Right $ C_ADDW rd'c rs2c
            _   -> Left (ReservedEncoding (fromIntegral w))
        _ -> Left (ReservedEncoding (fromIntegral w))
    0x5 ->  -- C.J (11-bit immediate, bit-scrambled)
      let raw  = cField w 15 2 .&. 0x7FF
          -- reconstruct J target from: j[11]|j[4]|j[9:8]|j[10]|j[6]|j[7]|j[3:1]|j[5]
          b11  = (raw `shiftR` 11) .&. 0x1
          b4   = (raw `shiftR` 10) .&. 0x1
          b9_8 = (raw `shiftR` 8)  .&. 0x3
          b10  = (raw `shiftR` 7)  .&. 0x1
          b6   = (raw `shiftR` 6)  .&. 0x1
          b7   = (raw `shiftR` 5)  .&. 0x1
          b3_1 = (raw `shiftR` 2)  .&. 0x7
          b5   = (raw `shiftR` 1)  .&. 0x1
          target = (b11 `shiftL` 11) .|. (b10 `shiftL` 10) .|. (b9_8 `shiftL` 8)
                 .|. (b7 `shiftL` 7) .|. (b6 `shiftL` 6) .|. (b5 `shiftL` 5)
                 .|. (b4 `shiftL` 4) .|. (b3_1 `shiftL` 1)
          sv   = fromIntegral (if b11 /= 0 then fromIntegral target - 0x1000 else target) :: Int16
      in Right $ C_J (Imm12 sv)
    0x6 ->  -- C.BEQZ
      let rs1c = mkCReg (cField w 9 7)
          v    = (cField w 12 12 `shiftL` 8) .|. (cField w 6 5 `shiftL` 6)
               .|. (cField w 2 2 `shiftL` 5) .|. (cField w 11 10 `shiftL` 3)
               .|. (cField w 4 3 `shiftL` 1)
          sv   = fromIntegral (if v .&. 0x100 /= 0 then fromIntegral v - 0x200 else v) :: Int16
      in Right $ C_BEQZ rs1c (Imm9 sv)
    0x7 ->  -- C.BNEZ
      let rs1c = mkCReg (cField w 9 7)
          v    = (cField w 12 12 `shiftL` 8) .|. (cField w 6 5 `shiftL` 6)
               .|. (cField w 2 2 `shiftL` 5) .|. (cField w 11 10 `shiftL` 3)
               .|. (cField w 4 3 `shiftL` 1)
          sv   = fromIntegral (if v .&. 0x100 /= 0 then fromIntegral v - 0x200 else v) :: Int16
      in Right $ C_BNEZ rs1c (Imm9 sv)
    f   -> Left (UnknownFunct3 0x1 (fromIntegral f))

decodeQ2 :: Word16 -> Word16 -> Either DecodeError Instruction
decodeQ2 w funct3 =
  let rdrs1 = Register (fromIntegral (cField w 11 7))
      rs2   = Register (fromIntegral (cField w 6 2))
      bit12 = cField w 12 12
  in case funct3 of
    0x0 ->  -- C.SLLI
      let shamt = (bit12 `shiftL` 5) .|. cField w 6 2
      in Right $ C_SLLI rdrs1 (UImm6 (fromIntegral shamt))
    0x2 ->  -- C.LWSP
      let uimm = (bit12 `shiftL` 5) .|. (cField w 6 4 `shiftL` 2) .|. (cField w 3 2 `shiftL` 6)
      in Right $ C_LWSP rdrs1 (UImm8 (fromIntegral uimm))
    0x3 ->  -- C.LDSP
      let uimm = (bit12 `shiftL` 5) .|. (cField w 6 5 `shiftL` 3) .|. (cField w 4 2 `shiftL` 6)
      in Right $ C_LDSP rdrs1 (UImm9 (fromIntegral uimm))
    0x4 ->
      let rs2val = fromIntegral (cField w 6 2) :: Int
      in case (bit12, unReg rdrs1, rs2val) of
        (0, _, 0) -> Right $ C_JR rdrs1
        (0, _, _) -> Right $ C_MV rdrs1 rs2
        (1, 0, 0) -> Right C_EBREAK
        (1, _, 0) -> Right $ C_JALR rdrs1
        (1, _, _) -> Right $ C_ADD rdrs1 rs2
        _         -> Left (ReservedEncoding (fromIntegral w))
    0x6 ->  -- C.SWSP
      let uimm = (cField w 12 9 `shiftL` 2) .|. (cField w 8 7 `shiftL` 6)
      in Right $ C_SWSP rs2 (UImm8 (fromIntegral uimm))
    0x7 ->  -- C.SDSP
      let uimm = (cField w 12 10 `shiftL` 3) .|. (cField w 9 7 `shiftL` 6)
      in Right $ C_SDSP rs2 (UImm9 (fromIntegral uimm))
    f   -> Left (UnknownFunct3 0x2 (fromIntegral f))
```

Add `Data.Word (Word16)` and `Data.Int (Int8)` to imports in Decode.hs.

- [ ] **Step 6: Run tests**

```bash
cabal test riscv-rig-test --test-options="--pattern=RV64C" 2>&1 | tail -10
```

Expected: All RV64C tests pass.

- [ ] **Step 7: Commit**

```bash
git add src/Core/Instruction.hs src/Core/Encode.hs src/Core/Decode.hs test/Test/Core/Compressed.hs
git commit -m "feat: add RV64C compressed instructions with encode16/decode16"
```

---

### Task 6: Generator Update for New Extensions

**Files:**
- Modify: `src/Generator/Random.hs`

**Context:** `Generator.Random` uses an `OpcodeCategory` sum type and `availableOpcodes` to dispatch generation. We need new categories for A/F/D/C. The existing `genReg`, `genImm12`, etc. helpers are reused. The `generateSequence` function already uses `Gen.element (availableOpcodes exts)` so adding new categories to `availableOpcodes` is sufficient.

- [ ] **Step 1: Add new OpcodeCategory constructors**

Replace the existing `OpcodeCategory` definition:

```haskell
data OpcodeCategory
  = AluR        -- R-type arithmetic (ADD, SUB, AND, ...)
  | AluI        -- I-type arithmetic (ADDI, ANDI, ...)
  | LoadOp      -- Load (LB, LH, LW, LD, ...)
  | StoreOp     -- Store (SB, SH, SW, SD)
  | BranchOp    -- Branch (BEQ, BNE, ...)
  | JumpOp      -- JAL, JALR
  | UpperImm    -- LUI, AUIPC
  | SystemOp    -- ECALL, EBREAK, FENCE, CSR
  | MulDiv      -- RV64M
  | PrivOp      -- MRET, SRET, WFI
  | AtomicOp    -- RV64A: LR/SC/AMO
  | FloatSOp    -- RV64F: single-precision FP
  | FloatDOp    -- RV64D: double-precision FP
  | CompressOp  -- RV64C: compressed
  deriving (Show, Eq, Ord, Enum, Bounded)
```

- [ ] **Step 2: Update `availableOpcodes`**

```haskell
availableOpcodes :: [Extension] -> [OpcodeCategory]
availableOpcodes exts =
  [ AluR, AluI, LoadOp, StoreOp, BranchOp, JumpOp, UpperImm, SystemOp ]
  <> [ MulDiv    | RV64M `elem` exts ]
  <> [ PrivOp    | RVPriv `elem` exts ]
  <> [ AtomicOp  | RV64A `elem` exts ]
  <> [ FloatSOp  | RV64F `elem` exts ]
  <> [ FloatDOp  | RV64D `elem` exts ]
  <> [ CompressOp | RV64C `elem` exts ]
```

- [ ] **Step 3: Add new generator functions**

Add to `genInstruction` case:

```haskell
    AtomicOp  -> genAtomic
    FloatSOp  -> genFloatS
    FloatDOp  -> genFloatD
    CompressOp -> genCompress
```

Add the generator implementations:

```haskell
genAqRl :: Gen AqRl
genAqRl = Gen.element [AqRlNone, AqRlRelease, AqRlAcquire, AqRlAcqRel]

genFPReg :: Gen FPRegister
genFPReg = FPRegister <$> Gen.word8 (Range.linear 0 31)

genRM :: Gen RoundingMode
genRM = Gen.element [RNE, RTZ, RDN, RUP, RMM, DYN]

genImm6 :: Gen Imm6
genImm6 = Imm6 <$> Gen.int8 (Range.linearFrom 0 (-32) 31)

genUImm7 :: Gen UImm7
genUImm7 = UImm7 <$> Gen.word8 (Range.linear 0 127)

genUImm8 :: Gen UImm8
genUImm8 = UImm8 <$> Gen.word8 (Range.linear 0 255)

genUImm9 :: Gen UImm9
genUImm9 = UImm9 <$> Gen.word16 (Range.linear 0 511)

genUImm10 :: Gen UImm10
genUImm10 = UImm10 <$> Gen.word16 (Range.linear 0 1023)

genImm9 :: Gen Imm9
genImm9 = Imm9 <$> Gen.int16 (Range.linearFrom 0 (-256) 254)

genImm10 :: Gen Imm10
genImm10 = Imm10 <$> Gen.int16 (Range.linearFrom 0 (-512) 496)

-- RV64A generator
genAtomic :: Gen Instruction
genAtomic = do
  rd  <- genNonZeroReg
  rs1 <- genNonZeroReg
  rs2 <- genNonZeroReg
  aq  <- genAqRl
  Gen.element
    [ LR_W rd rs1 aq, LR_D rd rs1 aq
    , SC_W rd rs1 rs2 aq, SC_D rd rs1 rs2 aq
    , AMOSWAP_W rd rs1 rs2 aq, AMOADD_W rd rs1 rs2 aq
    , AMOXOR_W  rd rs1 rs2 aq, AMOAND_W rd rs1 rs2 aq
    , AMOOR_W   rd rs1 rs2 aq, AMOMIN_W rd rs1 rs2 aq
    , AMOMAX_W  rd rs1 rs2 aq, AMOMINU_W rd rs1 rs2 aq
    , AMOMAXU_W rd rs1 rs2 aq
    , AMOSWAP_D rd rs1 rs2 aq, AMOADD_D rd rs1 rs2 aq
    , AMOXOR_D  rd rs1 rs2 aq, AMOAND_D rd rs1 rs2 aq
    , AMOOR_D   rd rs1 rs2 aq, AMOMIN_D rd rs1 rs2 aq
    , AMOMAX_D  rd rs1 rs2 aq, AMOMINU_D rd rs1 rs2 aq
    , AMOMAXU_D rd rs1 rs2 aq
    ]

-- RV64F generator
genFloatS :: Gen Instruction
genFloatS = do
  frd  <- genFPReg; frs1 <- genFPReg; frs2 <- genFPReg; frs3 <- genFPReg
  rd   <- genNonZeroReg; rs1 <- genNonZeroReg
  rm   <- genRM; imm <- genImm12
  Gen.element
    [ FLW frd rs1 imm, FSW frd rs1 imm
    , FADD_S frd frs1 frs2 rm, FSUB_S frd frs1 frs2 rm
    , FMUL_S frd frs1 frs2 rm, FDIV_S frd frs1 frs2 rm
    , FSQRT_S frd frs1 rm
    , FSGNJ_S frd frs1 frs2, FSGNJN_S frd frs1 frs2, FSGNJX_S frd frs1 frs2
    , FMIN_S frd frs1 frs2, FMAX_S frd frs1 frs2
    , FCVT_W_S rd frs1 rm, FCVT_WU_S rd frs1 rm
    , FCVT_L_S rd frs1 rm, FCVT_LU_S rd frs1 rm
    , FCVT_S_W frd rs1 rm, FCVT_S_WU frd rs1 rm
    , FCVT_S_L frd rs1 rm, FCVT_S_LU frd rs1 rm
    , FMV_X_W rd frs1, FMV_W_X frd rs1
    , FEQ_S rd frs1 frs2, FLT_S rd frs1 frs2, FLE_S rd frs1 frs2
    , FCLASS_S rd frs1
    , FMADD_S frd frs1 frs2 frs3 rm, FMSUB_S frd frs1 frs2 frs3 rm
    ]

-- RV64D generator
genFloatD :: Gen Instruction
genFloatD = do
  frd  <- genFPReg; frs1 <- genFPReg; frs2 <- genFPReg; frs3 <- genFPReg
  rd   <- genNonZeroReg; rs1 <- genNonZeroReg
  rm   <- genRM; imm <- genImm12
  Gen.element
    [ FLD frd rs1 imm, FSD frd rs1 imm
    , FADD_D frd frs1 frs2 rm, FSUB_D frd frs1 frs2 rm
    , FMUL_D frd frs1 frs2 rm, FDIV_D frd frs1 frs2 rm
    , FSQRT_D frd frs1 rm
    , FCVT_S_D frd frs1 rm, FCVT_D_S frd frs1 rm
    , FCVT_W_D rd frs1 rm, FCVT_WU_D rd frs1 rm
    , FCVT_L_D rd frs1 rm, FCVT_LU_D rd frs1 rm
    , FCVT_D_W frd rs1 rm, FMV_X_D rd frs1, FMV_D_X frd rs1
    , FEQ_D rd frs1 frs2, FLT_D rd frs1 frs2, FLE_D rd frs1 frs2
    , FCLASS_D rd frs1
    , FMADD_D frd frs1 frs2 frs3 rm, FMSUB_D frd frs1 frs2 frs3 rm
    ]

-- RV64C generator (restricted registers x8-x15 for compressed ops)
genCReg :: Gen Register  -- x8..x15
genCReg = Register <$> Gen.word8 (Range.linear 8 15)

genCompress :: Gen Instruction
genCompress = do
  rd   <- genNonZeroReg; rs1 <- genNonZeroReg; rs2 <- genNonZeroReg
  rd'  <- genCReg;       rs1' <- genCReg;       rs2' <- genCReg
  imm6 <- genImm6
  u7   <- genUImm7;   u8 <- genUImm8
  u9   <- genUImm9;   u10 <- genUImm10
  imm9_ <- genImm9;  imm10_ <- genImm10
  Gen.element
    [ C_ADDI rd imm6, C_ADDIW rd imm6, C_LI rd imm6
    , C_ADDI4SPN rd' u10, C_LW rd' rs1' u7, C_LD rd' rs1' u8
    , C_SW rs1' rs2' u7, C_SD rs1' rs2' u8
    , C_SRLI rd' (UImm6 (unUImm8 u8 `mod` 64))
    , C_SRAI rd' (UImm6 (unUImm8 u8 `mod` 64))
    , C_ANDI rd' imm6
    , C_SUB rd' rs2', C_XOR rd' rs2', C_OR rd' rs2', C_AND rd' rs2'
    , C_SUBW rd' rs2', C_ADDW rd' rs2'
    , C_J (Imm12 0)
    , C_BEQZ rs1' imm9_, C_BNEZ rs1' imm9_
    , C_SLLI rd (UImm6 (unUImm8 u8 `mod` 64))
    , C_LWSP rd u8, C_LDSP rd u9
    , C_JR rs1, C_MV rd rs2, C_EBREAK, C_JALR rs1, C_ADD rd rs2
    , C_SWSP rs2 u8, C_SDSP rs2 u9
    , C_ADDI16SP imm10_
    ]
```

- [ ] **Step 4: Run generator tests**

```bash
cabal test riscv-rig-test --test-options="--pattern=Generator" 2>&1 | tail -10
```

Expected: Existing generator tests pass. (No new test file for this task — generator correctness is tested via encode/decode.)

- [ ] **Step 5: Smoke test generate sequences**

```bash
cabal run riscv-rig -- generate --count 3 2>&1
```

Expected: Three "Generated sequence N (M instructions)" lines without errors.

- [ ] **Step 6: Commit**

```bash
git add src/Generator/Random.hs
git commit -m "feat: add generator support for RV64A/F/D/C extensions"
```

---

### Task 7: Coverage Bins Expansion

**Files:**
- Modify: `src/Coverage/Types.hs`
- Create: `test/Test/Coverage/Bins.hs`

**Context:** Phase 1 only has `OpcodeBin Text`. Phase 2 adds: `SequencePattern` (LR/SC pair, load-use, branch taken/not, etc.), `ValueCategory` (zero, max, min, aligned), `PatternBin`, `ValueBin`, and `OpcodeModeBin` (instruction × privilege level). The existing `allOpcodeBins` is extended to cover all extensions.

- [ ] **Step 1: Write failing tests in `test/Test/Coverage/Bins.hs`**

```haskell
module Test.Coverage.Bins (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Coverage.Types
import Core.Instruction (Extension(..))
import Core.Types       (PrivilegeLevel(..))
import Data.Map.Strict  (Map)
import qualified Data.Map.Strict as Map

tests :: TestTree
tests = testGroup "Coverage bins"
  [ testCase "PatternBin LrscPair has Show instance" $
      show (PatternBin LrscPair) @?= "PatternBin LrscPair"

  , testCase "ValueBin Zero has Show instance" $
      show (ValueBin Zero) @?= "ValueBin Zero"

  , testCase "OpcodeModeBin has Show instance" $
      show (OpcodeModeBin "ADD" Machine) @?= "OpcodeModeBin \"ADD\" Machine"

  , testCase "allCoverageBins includes PatternBin LrscPair" $
      PatternBin LrscPair `elem` allCoverageBins @?= True

  , testCase "allCoverageBins includes all ValueCategory variants" $
      all (\vc -> ValueBin vc `elem` allCoverageBins)
          [minBound..maxBound :: ValueCategory]
      @?= True

  , testCase "allCoverageBins includes OpcodeModeBin for ADDI × Machine" $
      OpcodeModeBin "ADDI" Machine `elem` allCoverageBins @?= True

  , testCase "allOpcodeBins still contains RV64I+M mnemonics" $
      OpcodeBin "ADD" `elem` allOpcodeBins @?= True

  , testCase "allOpcodeBins contains RV64A mnemonics" $
      OpcodeBin "LR_W" `elem` allOpcodeBins @?= True

  , testCase "allOpcodeBins contains RV64F mnemonics" $
      OpcodeBin "FADD_S" `elem` allOpcodeBins @?= True
  ]
```

- [ ] **Step 2: Run to confirm fails**

```bash
cabal test riscv-rig-test --test-options="--pattern=Coverage bins" 2>&1 | grep "error" | head -5
```

Expected: errors about missing constructors.

- [ ] **Step 3: Rewrite `src/Coverage/Types.hs`**

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

import Data.Map.Strict   (Map)
import Data.Text         (Text)
import Core.Types        (PrivilegeLevel(..))
import GHC.Generics      (Generic)

data SequencePattern
  = LrscPair            -- LR followed by SC on same address register
  | LrscSuccess         -- SC succeeds (rd = 0)
  | LrscFail            -- SC fails (rd = 1)
  | LoadUseDependency   -- load followed by instruction using load's rd
  | BranchTaken         -- branch instruction where target is taken
  | BranchNotTaken      -- branch where fall-through is taken
  | BackwardBranch      -- branch with negative offset (loop)
  | ForwardBranch       -- branch with positive offset
  | CallReturnPair      -- JAL followed by JALR on same register
  | TailCall            -- JAL with rd = x0
  | FenceBeforeAtomic   -- FENCE immediately before AMO or LR
  | ExceptionReturn     -- MRET or SRET instruction
  | WfiWithInterrupt    -- WFI instruction (waits for interrupt)
  | InstructionFusion   -- LUI immediately followed by ADDI (common fusion target)
  | CsrReadModifyWrite  -- CSRRS or CSRRC with nonzero rs1
  deriving (Show, Eq, Ord, Enum, Bounded, Generic)

data ValueCategory
  = Zero          -- operand = 0
  | One           -- operand = 1
  | AllOnes       -- operand = -1 (all bits set)
  | MaxPositive   -- operand = 2^(n-1) - 1
  | MinNegative   -- operand = -2^(n-1)
  | SmallPositive -- 1 < operand < 100
  | AlignedAddr   -- naturally aligned address
  | UnalignedAddr -- unaligned address
  deriving (Show, Eq, Ord, Enum, Bounded, Generic)

data CoverageBin
  = OpcodeBin     Text                    -- instruction mnemonic hit
  | PatternBin    SequencePattern         -- sequence pattern hit
  | ValueBin      ValueCategory           -- operand value category hit
  | OpcodeModeBin Text PrivilegeLevel     -- instruction × privilege level
  deriving (Show, Eq, Ord, Generic)

type HitCount    = Word
type CoverageMap = Map CoverageBin HitCount

-- All opcode bins for all Phase 2 extensions
allOpcodeBins :: [CoverageBin]
allOpcodeBins = map OpcodeBin $
  -- RV64I
  [ "ADD","SUB","ADDI","ADDIW","ADDW","SUBW"
  , "AND","OR","XOR","ANDI","ORI","XORI"
  , "SLL","SRL","SRA","SLLI","SRLI","SRAI"
  , "SLLIW","SRLIW","SRAIW","SLLW","SRLW","SRAW"
  , "SLT","SLTU","SLTI","SLTIU"
  , "LUI","AUIPC"
  , "LB","LH","LW","LD","LBU","LHU","LWU"
  , "SB","SH","SW","SD"
  , "BEQ","BNE","BLT","BGE","BLTU","BGEU"
  , "JAL","JALR"
  , "ECALL","EBREAK","FENCE","FENCE_I"
  , "CSRRW","CSRRS","CSRRC","CSRRWI","CSRRSI","CSRRCI"
  -- RV64M
  , "MUL","MULH","MULHSU","MULHU","DIV","DIVU","REM","REMU"
  , "MULW","DIVW","DIVUW","REMW","REMUW"
  -- Privileged
  , "MRET","SRET","WFI","SFENCE_VMA"
  -- RV64A
  , "LR_W","LR_D","SC_W","SC_D"
  , "AMOSWAP_W","AMOADD_W","AMOXOR_W","AMOAND_W","AMOOR_W"
  , "AMOMIN_W","AMOMAX_W","AMOMINU_W","AMOMAXU_W"
  , "AMOSWAP_D","AMOADD_D","AMOXOR_D","AMOAND_D","AMOOR_D"
  , "AMOMIN_D","AMOMAX_D","AMOMINU_D","AMOMAXU_D"
  -- RV64F
  , "FLW","FSW"
  , "FMADD_S","FMSUB_S","FNMADD_S","FNMSUB_S"
  , "FADD_S","FSUB_S","FMUL_S","FDIV_S","FSQRT_S"
  , "FSGNJ_S","FSGNJN_S","FSGNJX_S","FMIN_S","FMAX_S"
  , "FCVT_W_S","FCVT_WU_S","FCVT_L_S","FCVT_LU_S"
  , "FCVT_S_W","FCVT_S_WU","FCVT_S_L","FCVT_S_LU"
  , "FMV_X_W","FMV_W_X","FEQ_S","FLT_S","FLE_S","FCLASS_S"
  -- RV64D
  , "FLD","FSD"
  , "FMADD_D","FMSUB_D","FNMADD_D","FNMSUB_D"
  , "FADD_D","FSUB_D","FMUL_D","FDIV_D","FSQRT_D"
  , "FSGNJ_D","FSGNJN_D","FSGNJX_D","FMIN_D","FMAX_D"
  , "FCVT_S_D","FCVT_D_S"
  , "FCVT_W_D","FCVT_WU_D","FCVT_L_D","FCVT_LU_D"
  , "FCVT_D_W","FCVT_D_WU","FCVT_D_L","FCVT_D_LU"
  , "FMV_X_D","FMV_D_X","FEQ_D","FLT_D","FLE_D","FCLASS_D"
  -- RV64C
  , "C_ADDI4SPN","C_LW","C_LD","C_SW","C_SD"
  , "C_ADDI","C_ADDIW","C_LI","C_ADDI16SP","C_LUI"
  , "C_SRLI","C_SRAI","C_ANDI"
  , "C_SUB","C_XOR","C_OR","C_AND","C_SUBW","C_ADDW"
  , "C_J","C_BEQZ","C_BNEZ"
  , "C_SLLI","C_LWSP","C_LDSP"
  , "C_JR","C_MV","C_EBREAK","C_JALR","C_ADD"
  , "C_SWSP","C_SDSP"
  ]

-- All coverage bins: opcode + pattern + value + privilege cross
allCoverageBins :: [CoverageBin]
allCoverageBins =
  allOpcodeBins
  <> map PatternBin [minBound..maxBound]
  <> map ValueBin   [minBound..maxBound]
  <> [ OpcodeModeBin mnem priv
     | mnem <- coreOpcodeNames
     , priv <- [User, Supervisor, Machine]
     ]

-- Subset of opcodes that have meaningful privilege-level coverage
coreOpcodeNames :: [Text]
coreOpcodeNames =
  [ "ECALL","EBREAK","CSRRW","CSRRS","CSRRC","CSRRWI","CSRRSI","CSRRCI"
  , "MRET","SRET","WFI","SFENCE_VMA"
  , "LR_W","LR_D","SC_W","SC_D"
  ]
```

- [ ] **Step 4: Run coverage tests**

```bash
cabal test riscv-rig-test --test-options="--pattern=Coverage bins" 2>&1 | tail -10
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/Coverage/Types.hs test/Test/Coverage/Bins.hs
git commit -m "feat: add SequencePattern, ValueCategory, PatternBin, OpcodeModeBin to coverage model"
```

---

### Task 8: Core.ExtDeps — Extension Dependency Resolution

**Files:**
- Create: `src/Core/ExtDeps.hs`
- Create: `test/Test/Core/ExtDeps.hs`

**Context:** Some extensions depend on others: D requires F (which implies Zicsr), C requires I. `allDepsOf` computes the transitive closure so the generator always enables all required extensions.

- [ ] **Step 1: Write failing tests in `test/Test/Core/ExtDeps.hs`**

```haskell
module Test.Core.ExtDeps (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Core.Instruction (Extension(..))
import Core.ExtDeps
import qualified Data.Set as Set

tests :: TestTree
tests = testGroup "Extension dependencies"
  [ testCase "RV64I has no deps" $
      directDeps RV64I @?= []

  , testCase "RV64D depends on RV64F" $
      RV64F `elem` directDeps RV64D @?= True

  , testCase "allDepsOf {RV64D} includes RV64F and RV64I" $ do
      let deps = allDepsOf (Set.singleton RV64D)
      Set.member RV64F deps @?= True
      Set.member RV64I deps @?= True

  , testCase "allDepsOf {RV64A} includes RV64I" $ do
      let deps = allDepsOf (Set.singleton RV64A)
      Set.member RV64I deps @?= True

  , testCase "allDepsOf is idempotent" $ do
      let base = Set.fromList [RV64D, RV64A]
          once = allDepsOf base
          twice = allDepsOf once
      once @?= twice

  , testCase "resolveExtensions {RV64D} = {I,F,D}" $ do
      let resolved = resolveExtensions (Set.singleton RV64D)
      Set.member RV64I resolved @?= True
      Set.member RV64F resolved @?= True
      Set.member RV64D resolved @?= True
  ]
```

- [ ] **Step 2: Run to confirm fails**

```bash
cabal test riscv-rig-test --test-options="--pattern=Extension dependencies" 2>&1 | grep "error" | head -5
```

Expected: `Module not found: Core.ExtDeps`.

- [ ] **Step 3: Create `src/Core/ExtDeps.hs`**

```haskell
module Core.ExtDeps
  ( directDeps
  , allDepsOf
  , resolveExtensions
  ) where

import Core.Instruction (Extension(..))
import qualified Data.Set as Set

-- Direct dependencies of each extension
directDeps :: Extension -> [Extension]
directDeps RV64I  = []
directDeps RV64M  = [RV64I]
directDeps RV64A  = [RV64I]
directDeps RV64F  = [RV64I]       -- F also needs Zicsr (CSR for fcsr), but we model that as RV64I having CSR instructions
directDeps RV64D  = [RV64F, RV64I]
directDeps RV64C  = [RV64I]
directDeps RVPriv = [RV64I]

-- Transitive closure of dependencies starting from a set of extensions.
-- Returns the input set union all transitive dependencies.
allDepsOf :: Set.Set Extension -> Set.Set Extension
allDepsOf initial = go initial initial
  where
    go seen frontier
      | Set.null frontier = seen
      | otherwise =
          let newDeps = Set.fromList
                [ dep
                | ext <- Set.toList frontier
                , dep <- directDeps ext
                , dep `Set.notMember` seen
                ]
          in go (Set.union seen newDeps) newDeps

-- Resolve an extension set to include all transitive dependencies.
resolveExtensions :: Set.Set Extension -> Set.Set Extension
resolveExtensions = allDepsOf
```

- [ ] **Step 4: Run tests**

```bash
cabal test riscv-rig-test --test-options="--pattern=Extension dependencies" 2>&1 | tail -10
```

Expected: All 6 extension dependency tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/Core/ExtDeps.hs test/Test/Core/ExtDeps.hs
git commit -m "feat: add Core.ExtDeps extension dependency resolution"
```

---

### Task 9: Core.PMA — Physical Memory Attributes

**Files:**
- Create: `src/Core/PMA.hs`
- Create: `test/Test/Core/PMA.hs`

**Context:** PMA defines cacheable vs uncacheable vs vacant memory regions. This model is used by coverage bins (OpcodeMemBin in future phases) and by the Scenario system to describe test memory layouts.

- [ ] **Step 1: Write failing tests in `test/Test/Core/PMA.hs`**

```haskell
module Test.Core.PMA (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Core.PMA
import Data.Word (Word64)

tests :: TestTree
tests = testGroup "PMA model"
  [ testCase "defaultMemoryLayout has a main memory region" $ do
      let regions' = regions defaultMemoryLayout
      any (\e -> pmaType e == MainMemory) regions' @?= True

  , testCase "lookup 0x80000000 returns MainMemory" $ do
      let result = lookupPMA 0x80000000 defaultMemoryLayout
      fmap pmaType result @?= Just MainMemory

  , testCase "lookup 0x10000000 returns IOMemory" $ do
      let result = lookupPMA 0x10000000 defaultMemoryLayout
      fmap pmaType result @?= Just IOMemory

  , testCase "lookup 0x00000000 returns Nothing (vacant)" $ do
      lookupPMA 0x00000000 defaultMemoryLayout @?= Nothing

  , testCase "main memory is cacheable" $ do
      let result = lookupPMA 0x80000000 defaultMemoryLayout
      fmap pmaCacheable result @?= Just Cacheable

  , testCase "IO memory is uncacheable" $ do
      let result = lookupPMA 0x10000000 defaultMemoryLayout
      fmap pmaCacheable result @?= Just Uncacheable
  ]
```

- [ ] **Step 2: Create `src/Core/PMA.hs`**

```haskell
module Core.PMA
  ( MemoryType(..)
  , CacheabilityHint(..)
  , PMAEntry(..)
  , MemoryLayout(..)
  , defaultMemoryLayout
  , lookupPMA
  ) where

import Data.Word    (Word64)
import GHC.Generics (Generic)

data MemoryType
  = MainMemory   -- cacheable, coherent, idempotent
  | IOMemory     -- uncacheable, non-idempotent (read has side effects)
  | VacantMemory -- access raises access fault
  deriving (Show, Eq, Ord, Generic)

data CacheabilityHint
  = Cacheable
  | Uncacheable
  | WriteThrough
  deriving (Show, Eq, Ord, Generic)

data PMAEntry = PMAEntry
  { pmaBase       :: Word64
  , pmaSize       :: Word64
  , pmaType       :: MemoryType
  , pmaCacheable  :: CacheabilityHint
  , pmaExecutable :: Bool
  , pmaReadable   :: Bool
  , pmaWritable   :: Bool
  , pmaAtomic     :: Bool  -- supports LR/SC and AMO
  } deriving (Show, Eq, Generic)

data MemoryLayout = MemoryLayout
  { regions    :: [PMAEntry]
  , codeBase   :: Word64
  , dataBase   :: Word64
  , stackTop   :: Word64
  } deriving (Show, Eq, Generic)

-- Standard layout used by riscv-rig test programs
defaultMemoryLayout :: MemoryLayout
defaultMemoryLayout = MemoryLayout
  { regions =
      [ PMAEntry
          { pmaBase = 0x80000000, pmaSize = 0x10000000
          , pmaType = MainMemory, pmaCacheable = Cacheable
          , pmaExecutable = True, pmaReadable = True, pmaWritable = True, pmaAtomic = True
          }
      , PMAEntry
          { pmaBase = 0x10000000, pmaSize = 0x00001000
          , pmaType = IOMemory, pmaCacheable = Uncacheable
          , pmaExecutable = False, pmaReadable = True, pmaWritable = True, pmaAtomic = False
          }
      , PMAEntry
          { pmaBase = 0x02000000, pmaSize = 0x00010000
          , pmaType = IOMemory, pmaCacheable = Uncacheable
          , pmaExecutable = False, pmaReadable = True, pmaWritable = True, pmaAtomic = False
          }
      ]
  , codeBase = 0x80000000
  , dataBase = 0x80008000
  , stackTop = 0x80010000
  }

-- Find the PMA entry for a given physical address.
-- Returns Nothing if no region covers the address (implicitly VacantMemory).
lookupPMA :: Word64 -> MemoryLayout -> Maybe PMAEntry
lookupPMA addr layout =
  let matches e = addr >= pmaBase e && addr < pmaBase e + pmaSize e
  in case filter matches (regions layout) of
    []    -> Nothing
    (e:_) -> Just e
```

- [ ] **Step 3: Run tests**

```bash
cabal test riscv-rig-test --test-options="--pattern=PMA model" 2>&1 | tail -10
```

Expected: All 6 PMA tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/Core/PMA.hs test/Test/Core/PMA.hs
git commit -m "feat: add Core.PMA physical memory attributes model"
```

---

### Task 10: CoSim.Shrink — Sequence Shrinking

**Files:**
- Create: `src/CoSim/Shrink.hs`
- Create: `test/Test/CoSim/Shrink.hs`

**Context:** When CoSim finds a mismatch, it should shrink the instruction sequence to the smallest reproducing case. The algorithm is delta-debugging: try removing each instruction, keep the sequence if the predicate still holds, repeat until no further reduction is possible.

- [ ] **Step 1: Write failing tests in `test/Test/CoSim/Shrink.hs`**

```haskell
module Test.CoSim.Shrink (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Core.Types
import Core.Instruction
import CoSim.Shrink

tests :: TestTree
tests = testGroup "CoSim.Shrink"
  [ testCase "shrink empty sequence stays empty" $ do
      result <- shrinkSequence (\_ -> return True) []
      result @?= []

  , testCase "shrink removes instructions that dont affect predicate" $ do
      -- Predicate: sequence contains at least one ADDI instruction
      let seq_ = [ ADD x1 x2 x3, ADDI x1 x2 (Imm12 0), SUB x3 x4 x5, ADDI x2 x3 (Imm12 1) ]
          pred_ instrs = return $ any isAddi instrs
          isAddi (ADDI{}) = True; isAddi _ = False
      result <- shrinkSequence pred_ seq_
      -- Result must still have at least one ADDI
      any isAddi result @?= True
      -- Result should be shorter (ADD/SUB removed)
      length result < length seq_ @?= True

  , testCase "shrink stops when no instruction can be removed" $ do
      -- Predicate: sequence has exactly one instruction
      let seq_ = [ADDI x1 x2 (Imm12 5)]
          pred_ instrs = return $ length instrs == 1
      result <- shrinkSequence pred_ seq_
      result @?= [ADDI x1 x2 (Imm12 5)]

  , testCase "shrink returns empty when predicate satisfied by empty" $ do
      let seq_ = [ADD x1 x2 x3, SUB x4 x5 x6]
          pred_ _ = return True  -- always true, even empty
      result <- shrinkSequence pred_ seq_
      result @?= []
  ]
```

- [ ] **Step 2: Create `src/CoSim/Shrink.hs`**

```haskell
module CoSim.Shrink
  ( shrinkSequence
  ) where

import Core.Instruction (Instruction)

-- | Shrink an instruction sequence to a minimal subset that still satisfies
-- the predicate. Uses delta-debugging: repeatedly tries to remove single
-- instructions, keeping the removal if the predicate still holds.
--
-- The predicate returns True if the sequence still "triggers the bug" or
-- otherwise satisfies the condition of interest.
--
-- Time complexity: O(n^2) in the sequence length. For sequences of 100+
-- instructions, consider using the binary-split variant.
shrinkSequence
  :: ([Instruction] -> IO Bool)  -- predicate
  -> [Instruction]               -- initial sequence
  -> IO [Instruction]
shrinkSequence pred_ initial = do
  initialHolds <- pred_ initial
  if not initialHolds
    then return initial  -- predicate not even satisfied by original; return as-is
    else go initial
  where
    go [] = return []
    go current = do
      -- Try to remove the first instruction that can be removed
      maybeSmaller <- tryRemoveOne pred_ current
      case maybeSmaller of
        Nothing      -> return current       -- nothing can be removed
        Just smaller -> go smaller           -- recurse with smaller sequence

-- Try removing each instruction one by one; return the first sequence
-- for which the predicate still holds, or Nothing if none.
tryRemoveOne
  :: ([Instruction] -> IO Bool)
  -> [Instruction]
  -> IO (Maybe [Instruction])
tryRemoveOne _     []  = return Nothing
tryRemoveOne pred_ xs  = go 0
  where
    n = length xs
    go i
      | i >= n    = return Nothing
      | otherwise = do
          let candidate = take i xs <> drop (i + 1) xs
          holds <- pred_ candidate
          if holds
            then return (Just candidate)
            else go (i + 1)
```

- [ ] **Step 3: Run tests**

```bash
cabal test riscv-rig-test --test-options="--pattern=CoSim.Shrink" 2>&1 | tail -10
```

Expected: All 4 shrink tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/CoSim/Shrink.hs test/Test/CoSim/Shrink.hs
git commit -m "feat: add CoSim.Shrink delta-debugging sequence shrinking"
```

---

### Task 11: Scenario System

**Files:**
- Create: `src/Scenario/Types.hs`
- Create: `src/Scenario/Registry.hs`
- Create: `src/Scenario/Builtin/LrscInterrupt.hs`
- Create: `test/Test/Scenario/Registry.hs`

**Context:** Scenarios describe test "stories" — sequences of phases, each with constraints and events. Phase 1's generator produces random sequences; the Scenario system adds structured intent. `ScenarioSpec` is the top-level descriptor; `ScenarioPhase` holds constraints + directives + events for one phase.

- [ ] **Step 1: Write failing tests in `test/Test/Scenario/Registry.hs`**

```haskell
module Test.Scenario.Registry (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Scenario.Registry
import Scenario.Types

tests :: TestTree
tests = testGroup "Scenario registry"
  [ testCase "allScenarios is non-empty" $
      null allScenarios @?= False

  , testCase "findByName returns Nothing for unknown name" $
      findByName "nonexistent-scenario" @?= Nothing

  , testCase "findByName finds lrsc-timer-interrupt" $
      fmap sName (findByName "lrsc-timer-interrupt") @?= Just "lrsc-timer-interrupt"

  , testCase "findByTag Atomic returns at least one scenario" $
      null (findByTag Atomic) @?= False

  , testCase "lrsc scenario has RV64A in sExtensions" $ do
      let Just spec = findByName "lrsc-timer-interrupt"
      RV64A `elem` sExtensions spec @?= True
  ]
```

- [ ] **Step 2: Create `src/Scenario/Types.hs`**

```haskell
module Scenario.Types
  ( Tag(..)
  , Event(..)
  , Directive(..)
  , ScenarioPhase(..)
  , ScenarioSpec(..)
  , emptyPhase
  ) where

import Core.Types       (PrivilegeLevel(..))
import Core.Instruction (Extension(..), Instruction)
import Coverage.Types   (CoverageBin)
import Constraint.Types (ConstraintSet, emptyConstraintSet)
import Data.Text        (Text)
import GHC.Generics     (Generic)

-- Classification tags for scenarios
data Tag
  = Atomic
  | Interrupt
  | Privileged
  | CornerCase
  | Memory
  | FP
  | Compressed
  | MultiCore
  deriving (Show, Eq, Ord, Enum, Bounded, Generic)

-- Events injected between phases by the harness / CoSim engine
data Event
  = InjectTimerInterrupt           -- set MTIP, trigger interrupt before next instr
  | InjectSoftwareInterrupt        -- set MSIP
  | SetPrivilege PrivilegeLevel    -- switch to privilege level via MRET sequence
  | FlushTLB                       -- emit SFENCE.VMA
  | FlushCache                     -- emit FENCE
  deriving (Show, Eq, Generic)

-- Directives within a phase
data Directive
  = EmitInstr Instruction          -- force-insert a specific instruction
  | RandomN   Int Int              -- generate N..M random instructions from phase constraints
  | UseConstraintNamed Text        -- add a named constraint from the library
  deriving (Show, Eq, Generic)

-- One phase of a scenario
data ScenarioPhase = ScenarioPhase
  { spName        :: Text
  , spConstraints :: ConstraintSet
  , spDirectives  :: [Directive]
  , spEvents      :: [Event]
  } deriving (Generic)

emptyPhase :: Text -> ScenarioPhase
emptyPhase name = ScenarioPhase
  { spName        = name
  , spConstraints = emptyConstraintSet
  , spDirectives  = []
  , spEvents      = []
  }

-- Top-level scenario descriptor
data ScenarioSpec = ScenarioSpec
  { sName        :: Text
  , sTags        :: [Tag]
  , sDescription :: Text
  , sExtensions  :: [Extension]
  , sClaims      :: [CoverageBin]
  , sPhases      :: [ScenarioPhase]
  } deriving (Generic)
```

- [ ] **Step 3: Create `src/Scenario/Registry.hs`**

```haskell
module Scenario.Registry
  ( allScenarios
  , findByName
  , findByTag
  ) where

import Scenario.Types
import Data.Text  (Text)
import Data.Maybe (listToMaybe)
import qualified Scenario.Builtin.LrscInterrupt as S001

allScenarios :: [ScenarioSpec]
allScenarios =
  [ S001.spec
  ]

findByName :: Text -> Maybe ScenarioSpec
findByName name = listToMaybe (filter (\s -> sName s == name) allScenarios)

findByTag :: Tag -> [ScenarioSpec]
findByTag tag = filter (elem tag . sTags) allScenarios
```

- [ ] **Step 4: Create `src/Scenario/Builtin/LrscInterrupt.hs`**

```haskell
-- | Scenario: LR.D / SC.D pair with timer interrupt injected between them.
-- Tests that a CPU correctly invalidates the reservation when an interrupt
-- occurs between LR and SC, causing SC to fail (rd = 1).
module Scenario.Builtin.LrscInterrupt (spec) where

import Scenario.Types
import Core.Types       (AqRl(..), x1, x2)
import Core.Instruction (Extension(..), Instruction(..))
import Coverage.Types   (CoverageBin(..), SequencePattern(..))

spec :: ScenarioSpec
spec = ScenarioSpec
  { sName        = "lrsc-timer-interrupt"
  , sTags        = [Atomic, Interrupt, Privileged, CornerCase]
  , sDescription =
      "LR.D/SC.D pair with a timer interrupt injected between them. \
      \Tests whether the reservation is correctly invalidated. \
      \SC.D should fail (rd = 1) because the interrupt breaks the reservation."
  , sExtensions  = [RV64A, RVPriv]
  , sClaims      =
      [ PatternBin LrscPair
      , PatternBin LrscFail
      ]
  , sPhases      =
      [ emptyPhase "setup"
      , ScenarioPhase
          { spName        = "lr-acquire"
          , spConstraints = emptyConstraintSet
          , spDirectives  =
              [ EmitInstr (LR_D x1 x2 AqRlAcquire)
              , RandomN 0 3
              ]
          , spEvents      = []
          }
      , ScenarioPhase
          { spName        = "interrupt-injection"
          , spConstraints = emptyConstraintSet
          , spDirectives  = []
          , spEvents      = [InjectTimerInterrupt]
          }
      , ScenarioPhase
          { spName        = "sc-verify"
          , spConstraints = emptyConstraintSet
          , spDirectives  =
              [ EmitInstr (SC_D x1 x2 x1 AqRlRelease)
              ]
          , spEvents      = []
          }
      ]
  }
```

- [ ] **Step 5: Run tests**

```bash
cabal test riscv-rig-test --test-options="--pattern=Scenario registry" 2>&1 | tail -10
```

Expected: All 5 scenario registry tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/Scenario/Types.hs src/Scenario/Registry.hs src/Scenario/Builtin/LrscInterrupt.hs test/Test/Scenario/Registry.hs
git commit -m "feat: add Scenario system (Types, Registry, LrscInterrupt example)"
```

---

### Task 12: CoSim.Sail — Sail ISA Simulator Integration

**Files:**
- Create: `src/CoSim/Sail.hs`

**Context:** Mirrors `CoSim.Spike` but for the Sail ISA simulator. Gracefully skip tests if `sail-riscv` is not on PATH. Reuses `SpikeResult` (renamed mentally as the result type is the same shape).

- [ ] **Step 1: Create `src/CoSim/Sail.hs`**

```haskell
module CoSim.Sail
  ( SailConfig(..)
  , SailISA(..)
  , defaultSailConfig
  , checkSailExists
  , runSail
  ) where

import CoSim.Spike      (SpikeResult(..), SpikeConfig(..))
import System.Exit      (ExitCode(..))
import System.Process   (readProcessWithExitCode)
import System.IO.Error  (tryIOError)
import Data.Time.Clock  (NominalDiffTime)

data SailISA = SailRV64GC | SailRV32GC
  deriving (Show, Eq)

data SailConfig = SailConfig
  { scSailPath :: FilePath          -- path to sail-riscv binary
  , scSailISA  :: SailISA
  , scTimeout  :: NominalDiffTime
  }

defaultSailConfig :: SailConfig
defaultSailConfig = SailConfig
  { scSailPath = "sail-riscv"
  , scSailISA  = SailRV64GC
  , scTimeout  = 30
  }

checkSailExists :: IO Bool
checkSailExists = do
  result <- tryIOError (readProcessWithExitCode "sail-riscv" ["--help"] "")
  return $ case result of
    Left  _          -> False
    Right (ExitSuccess,    _, _) -> True
    Right (ExitFailure _, _, _)  -> True  -- present but returned non-zero is fine

runSail :: SailConfig -> FilePath -> IO SpikeResult
runSail cfg elfPath = do
  let args = [ "--no-trace"
             , if scSailISA cfg == SailRV64GC then "rv64" else "rv32"
             , elfPath
             ]
  (exitCode, stdout, stderr) <- readProcessWithExitCode (scSailPath cfg) args ""
  return SpikeResult
    { srExitCode = exitCode
    , srStdout   = stdout
    , srStderr   = stderr
    , srLog      = []      -- Sail log parsing is future work
    }
```

Note: `SpikeResult` is imported from `CoSim.Spike`. If `CoSim.Spike` does not export it, update that module's export list to include `SpikeResult(..)`.

- [ ] **Step 2: Verify it compiles**

```bash
cabal build 2>&1 | tail -5
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add src/CoSim/Sail.hs
git commit -m "feat: add CoSim.Sail Sail ISA simulator integration (graceful skip)"
```

---

### Task 13: Cabal + Test Suite Update

**Files:**
- Modify: `riscv-rig.cabal`
- Modify: `test/Spec.hs`

**Context:** All new source modules must appear in `exposed-modules` in the cabal file. All new test modules must be added to `other-modules` in `riscv-rig-test` and imported in `test/Spec.hs`. Run the full 45+ test suite at the end.

- [ ] **Step 1: Update `riscv-rig.cabal` library exposed-modules**

The current `exposed-modules` ends with `CoSim.Batch`. Add all new modules:

```
    Core.ExtDeps
    Core.PMA
    CoSim.Shrink
    CoSim.Sail
    Scenario.Types
    Scenario.Registry
    Scenario.Builtin.LrscInterrupt
```

- [ ] **Step 2: Update `riscv-rig.cabal` test-suite other-modules**

In `test-suite riscv-rig-test`, add to `other-modules`:

```
    Test.Core.Atomic
    Test.Core.FloatInstr
    Test.Core.Compressed
    Test.Core.ExtDeps
    Test.Core.PMA
    Test.Coverage.Bins
    Test.CoSim.Shrink
    Test.Scenario.Registry
```

- [ ] **Step 3: Update `test/Spec.hs`**

```haskell
module Main (main) where

import Test.Tasty
import qualified Test.Core.Encode          as Encode
import qualified Test.Core.Decode          as Decode
import qualified Test.Core.Atomic          as Atomic
import qualified Test.Core.FloatInstr      as FloatInstr
import qualified Test.Core.Compressed      as Compressed
import qualified Test.Core.ExtDeps         as ExtDeps
import qualified Test.Core.PMA             as PMA
import qualified Test.Constraint.Solver    as Solver
import qualified Test.Generator.Random     as Random
import qualified Test.Coverage.Accumulator as Accumulator
import qualified Test.Coverage.Bins        as Bins
import qualified Test.ELF.FlatBinary       as ELFBinary
import qualified Test.CoSim.Spike          as Spike
import qualified Test.CoSim.Shrink         as Shrink
import qualified Test.Scenario.Registry    as Registry

main :: IO ()
main = defaultMain $ testGroup "riscv-rig"
  [ Encode.tests
  , Decode.tests
  , Atomic.tests
  , FloatInstr.tests
  , Compressed.tests
  , ExtDeps.tests
  , PMA.tests
  , Solver.tests
  , Random.tests
  , Accumulator.tests
  , Bins.tests
  , ELFBinary.tests
  , Spike.tests
  , Shrink.tests
  , Registry.tests
  ]
```

- [ ] **Step 4: Run full test suite**

```bash
cabal test riscv-rig-test --test-show-details=direct 2>&1 | tail -20
```

Expected output (final lines):
```
All N tests passed (X.XXs)
```

Where N ≥ 45 (Phase 1's 45 plus all new Phase 2 tests). If any test fails, read the output, fix the issue, and re-run.

- [ ] **Step 5: Verify CLI still works**

```bash
cabal run riscv-rig -- version
# riscv-rig 0.1.0

cabal run riscv-rig -- generate --count 3
# Generated sequence 1 (N instructions)
# Generated sequence 2 (N instructions)
# Generated sequence 3 (N instructions)
```

- [ ] **Step 6: Commit**

```bash
git add riscv-rig.cabal test/Spec.hs
git commit -m "build: expose all Phase 2 modules; add Phase 2 test modules to test suite"
```

---

## Spec Coverage Self-Review

| Phase 2 Spec Item | Covered By |
|---|---|
| RV64A ADT + encode/decode | Task 2 |
| RV64F ADT + encode/decode | Task 3 |
| RV64D ADT + encode/decode | Task 4 |
| RV64C ADT + encode16/decode16 | Task 5 |
| Generator supports A/F/D/C | Task 6 |
| PMA model (Cacheable/IO/Vacant) | Task 9 |
| Scenario system (Phase, Event, registry) | Task 11 |
| Extension dependency resolution | Task 8 |
| UNSAT core detection | **Already in Phase 1** (`Constraint.Solver.checkFeasibility`) |
| Density estimation | **Already in Phase 1** (`Constraint.Solver.estimateDensity`) |
| Sail CoSim integration | Task 12 |
| Shrinking | Task 10 |
| ELF generation | **Already in Phase 1** (`ELF.FlatBinary`) |
| Privilege level coverage (M/S/U bins) | Task 7 (`OpcodeModeBin`) |
| Sequence pattern coverage bins | Task 7 (`PatternBin`, `SequencePattern`) |
| FP register aliases | Task 1 |
| Compressed immediate types | Task 1 |
| Cabal + tests | Task 13 |
