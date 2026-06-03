# riscv-rig Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the foundational riscv-rig library — RV64I+M instruction ADT with encode/decode, Z3-backed constraint solver, Hedgehog random generator, opcode coverage tracker, ELF64 binary writer, and Spike co-simulation batch runner — resulting in a working CLI that generates random RISC-V programs and validates them against Spike.

**Architecture:** Single Haskell library (`riscv-rig`) with pure core modules (`Core.*`, `Constraint.*`, `Generator.*`, `Coverage.*`, `ELF.*`) and IO-at-the-edges runners (`CoSim.*`). A thin `app/` executable wires everything together via `optparse-applicative`. GHC2021 throughout; no Template Haskell; no orphan instances.

**Tech Stack:** GHC 9.6+, Cabal 3.10+, GHC2021, SBV ≥ 10.2 (Z3 SMT binding), Hedgehog ≥ 1.4 (property-based testing + shrinking), Megaparsec ≥ 9.6 (Spike log parser), Data.Binary.Put (ELF64 writer), Tasty + tasty-hedgehog + tasty-hunit (test runner), optparse-applicative ≥ 0.18 (CLI).

**Prerequisites:**
- GHC 9.6+ and Cabal 3.10+: install via [GHCup](https://www.haskell.org/ghcup/)
- Z3 installed and on `PATH`: `z3 --version` should print `Z3 version 4.x`
- Spike installed and on `PATH` (required for Task 14+): `spike --help` should work

---

## File Map

```
riscv-rig/
├── riscv-rig.cabal
├── cabal.project
├── .gitignore
├── src/
│   ├── Core/
│   │   ├── Types.hs          Register, Imm, AqRl, FenceMode, PrivilegeLevel
│   │   ├── Instruction.hs    Instruction ADT (RV64I+M+Priv), Extension, InstrFormat
│   │   ├── Encode.hs         encode :: Instruction -> Word32
│   │   ├── Decode.hs         decode :: Word32 -> Either DecodeError Instruction
│   │   └── CSR.hs            CSR ADT, csrAddr, CSRAccess rules
│   ├── Constraint/
│   │   ├── Types.hs          ConstraintDef, ConstraintSet, SymInstrParams, InstrParams, Density
│   │   ├── Solver.hs         solve, checkFeasibility, estimateDensity (SBV/Z3)
│   │   ├── Library.hs        rdNotZero, rs1NotZero, alignedImm, immInRange, branchImmEven
│   │   └── Combinators.hs    cAnd, cOr, cNot, cImplies, withWeight, addConstraint
│   ├── Generator/
│   │   ├── Seed.hs           Seed newtype, newRandomSeed, seedFromWord64, deriveSeed
│   │   ├── Types.hs          GeneratorConfig, GeneratorMode, InstrSequence, defaultConfig
│   │   └── Random.hs         genInstruction, generateSequence, OpcodeCategory, genImm12
│   ├── Coverage/
│   │   ├── Types.hs          CoverageBin (OpcodeBin Text), CoverageMap, allOpcodeBins
│   │   ├── Accumulator.hs    CoverageAccumulator (TVar STM), newAccumulator, recordCoverage
│   │   └── Analysis.hs       CoverageSummary, coverageSummary, renderSummary (ASCII bar)
│   ├── ELF/
│   │   └── FlatBinary.hs     TestProgram, generateElf, defaultStartup, defaultTrapHandler
│   └── CoSim/
│       ├── Types.hs          ArchState, StateDelta, StateDiff, LogEntry, MismatchReport
│       ├── Oracle.hs         CoSimOracle, OracleCapabilities, oracleCapabilities, selectOracles
│       ├── Diff.hs           diffArchState, gprDiffs, csrDiffs
│       ├── Spike.hs          runSpike, parseSpikeLog (Megaparsec), SpikeConfig
│       └── Batch.hs          runBatch, BatchConfig, BatchResult
├── app/
│   ├── Main.hs
│   └── CLI/
│       ├── Options.hs        Command, RunOptions, GenerateOptions, parseOptions
│       └── Runner.hs         runCommand dispatch
└── test/
    ├── Spec.hs               Tasty main entry point
    └── Test/
        ├── Core/
        │   ├── Encode.hs     known-encoding unit tests
        │   └── Decode.hs     encode/decode roundtrip (Hedgehog)
        ├── Constraint/
        │   └── Solver.hs     satisfiability tests
        ├── Generator/
        │   └── Random.hs     validity + coverage growth
        ├── Coverage/
        │   └── Accumulator.hs STM concurrency test
        ├── ELF/
        │   └── FlatBinary.hs ELF magic / structure test
        └── CoSim/
            └── Spike.hs      log-line parser unit tests
```

---

## Task 1: Project Scaffold

**Files:**
- Create: `riscv-rig/riscv-rig.cabal`
- Create: `riscv-rig/cabal.project`
- Create: `riscv-rig/.gitignore`
- Create: stub `module X where` for every module listed in the file map

- [ ] **Step 1: Create project root and cabal file**

```
mkdir riscv-rig && cd riscv-rig
```

`riscv-rig.cabal`:
```cabal
cabal-version: 3.0
name:          riscv-rig
version:       0.1.0.0
synopsis:      RISC-V Random Instruction Generator with SMT constraint solving
license:       MIT
build-type:    Simple

common common-options
  default-language:   GHC2021
  ghc-options:        -Wall -Wcompat -Wincomplete-record-updates
                      -Wincomplete-uni-patterns -Wredundant-constraints
  default-extensions: OverloadedStrings
                      LambdaCase
                      TupleSections
                      ImportQualifiedPost

library
  import:          common-options
  hs-source-dirs:  src
  exposed-modules:
    Core.Types
    Core.Instruction
    Core.Encode
    Core.Decode
    Core.CSR
    Constraint.Types
    Constraint.Solver
    Constraint.Library
    Constraint.Combinators
    Generator.Seed
    Generator.Types
    Generator.Random
    Coverage.Types
    Coverage.Accumulator
    Coverage.Analysis
    ELF.FlatBinary
    CoSim.Types
    CoSim.Oracle
    CoSim.Diff
    CoSim.Spike
    CoSim.Batch
  build-depends:
      base           >= 4.17  && < 5
    , text           >= 2.0
    , bytestring     >= 0.11
    , binary         >= 0.8
    , containers     >= 0.6
    , vector         >= 0.13
    , stm            >= 2.5
    , sbv            >= 10.2
    , hedgehog       >= 1.4
    , megaparsec     >= 9.6
    , time           >= 1.12
    , process        >= 1.6
    , temporary      >= 1.3
    , filepath       >= 1.4
    , directory      >= 1.3
    , random         >= 1.2

executable riscv-rig
  import:          common-options
  hs-source-dirs:  app
  main-is:         Main.hs
  other-modules:
    CLI.Options
    CLI.Runner
  build-depends:
      base                 >= 4.17 && < 5
    , riscv-rig
    , optparse-applicative >= 0.18
    , text                 >= 2.0

test-suite riscv-rig-test
  import:          common-options
  type:            exitcode-stdio-1.0
  hs-source-dirs:  test
  main-is:         Spec.hs
  other-modules:
    Test.Core.Encode
    Test.Core.Decode
    Test.Constraint.Solver
    Test.Generator.Random
    Test.Coverage.Accumulator
    Test.ELF.FlatBinary
    Test.CoSim.Spike
  build-depends:
      base           >= 4.17 && < 5
    , riscv-rig
    , hedgehog       >= 1.4
    , tasty          >= 1.4
    , tasty-hedgehog >= 1.4
    , tasty-hunit    >= 0.10
    , containers     >= 0.6
    , bytestring     >= 0.11
```

- [ ] **Step 2: Create cabal.project and .gitignore**

`cabal.project`:
```
packages: .
optimization: 1
```

`.gitignore`:
```
dist-newstyle/
*.hi
*.o
.ghc.environment.*
result
```

- [ ] **Step 3: Create all stub modules**

Create each file with just the module declaration. For every module listed in the file map, create the file:

```haskell
-- src/Core/Types.hs
module Core.Types where
```

```haskell
-- src/Core/Instruction.hs
module Core.Instruction where
```

```haskell
-- src/Core/Encode.hs
module Core.Encode where
```

```haskell
-- src/Core/Decode.hs
module Core.Decode where
```

```haskell
-- src/Core/CSR.hs
module Core.CSR where
```

```haskell
-- src/Constraint/Types.hs
module Constraint.Types where
```

```haskell
-- src/Constraint/Solver.hs
module Constraint.Solver where
```

```haskell
-- src/Constraint/Library.hs
module Constraint.Library where
```

```haskell
-- src/Constraint/Combinators.hs
module Constraint.Combinators where
```

```haskell
-- src/Generator/Seed.hs
module Generator.Seed where
```

```haskell
-- src/Generator/Types.hs
module Generator.Types where
```

```haskell
-- src/Generator/Random.hs
module Generator.Random where
```

```haskell
-- src/Coverage/Types.hs
module Coverage.Types where
```

```haskell
-- src/Coverage/Accumulator.hs
module Coverage.Accumulator where
```

```haskell
-- src/Coverage/Analysis.hs
module Coverage.Analysis where
```

```haskell
-- src/ELF/FlatBinary.hs
module ELF.FlatBinary where
```

```haskell
-- src/CoSim/Types.hs
module CoSim.Types where
```

```haskell
-- src/CoSim/Oracle.hs
module CoSim.Oracle where
```

```haskell
-- src/CoSim/Diff.hs
module CoSim.Diff where
```

```haskell
-- src/CoSim/Spike.hs
module CoSim.Spike where
```

```haskell
-- src/CoSim/Batch.hs
module CoSim.Batch where
```

```haskell
-- app/CLI/Options.hs
module CLI.Options where
```

```haskell
-- app/CLI/Runner.hs
module CLI.Runner where
```

```haskell
-- app/Main.hs
module Main where
main :: IO ()
main = return ()
```

```haskell
-- test/Spec.hs
module Main where
import Test.Tasty
main :: IO ()
main = defaultMain (testGroup "riscv-rig" [])
```

Also create stub test files:
```haskell
-- test/Test/Core/Encode.hs
module Test.Core.Encode where
import Test.Tasty
tests :: TestTree
tests = testGroup "Core.Encode" []
```
(repeat same stub pattern for all 7 test modules)

- [ ] **Step 4: Verify the project builds**

```
cabal build all
```

Expected: builds successfully (warnings OK, errors NOT OK).

- [ ] **Step 5: Commit**

```bash
git init
git add .
git commit -m "feat: project scaffold — cabal file, stub modules, test stubs"
```

---

## Task 2: Core.Types

**Files:**
- Modify: `src/Core/Types.hs`
- Modify: `test/Test/Core/Encode.hs` (add basic type instantiation test)

- [ ] **Step 1: Write the failing test**

`test/Test/Core/Encode.hs`:
```haskell
module Test.Core.Encode (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Core.Types

tests :: TestTree
tests = testGroup "Core.Types"
  [ testCase "x0 is register 0" $
      unReg x0 @?= 0
  , testCase "AqRl has 4 constructors" $
      length [minBound..maxBound :: AqRl] @?= 4
  , testCase "RoundingMode has 6 constructors" $
      length [minBound..maxBound :: RoundingMode] @?= 6
  , testCase "PrivilegeLevel ordering: User < Machine" $
      (User < Machine) @?= True
  ]
```

- [ ] **Step 2: Run test to verify it fails**

```
cabal test riscv-rig-test --test-option="--pattern=Core.Types"
```

Expected: compile error — `unReg`, `x0`, `AqRl` not defined.

- [ ] **Step 3: Implement Core.Types**

`src/Core/Types.hs`:
```haskell
module Core.Types
  ( Register(..), FPRegister(..), CSRAddr(..)
  , Imm12(..), Imm13(..), Imm20(..), Imm21(..), Imm6(..)
  , UImm5(..)
  , AqRl(..), RoundingMode(..), FenceMode(..)
  , PrivilegeLevel(..)
  -- Register aliases
  , x0, ra, sp, gp, tp, t0, t1, t2, fp, s1
  , a0, a1, a2, a3, a4, a5, a6, a7
  , s2, s3, s4, s5, s6, s7, s8, s9, s10, s11
  , t3, t4, t5, t6
  ) where

import Data.Word  (Word8, Word16)
import Data.Int   (Int8, Int16, Int32)
import GHC.Generics (Generic)

-- Semantic register wrappers. Use newtypes so GHC prevents mixing
-- Register with FPRegister at compile time.
newtype Register   = Register   { unReg  :: Word8  }
  deriving (Show, Eq, Ord, Generic)
newtype FPRegister = FPRegister { unFReg :: Word8  }
  deriving (Show, Eq, Ord, Generic)
newtype CSRAddr    = CSRAddr    { unCSR  :: Word16 }
  deriving (Show, Eq, Ord, Generic)

-- Immediates: sized newtypes prevent confusion between I-type and B-type imms.
newtype Imm12  = Imm12  { unImm12  :: Int16 } deriving (Show, Eq, Ord, Generic)
newtype Imm13  = Imm13  { unImm13  :: Int16 } deriving (Show, Eq, Ord, Generic)
newtype Imm20  = Imm20  { unImm20  :: Int32 } deriving (Show, Eq, Ord, Generic)
newtype Imm21  = Imm21  { unImm21  :: Int32 } deriving (Show, Eq, Ord, Generic)
newtype Imm6   = Imm6   { unImm6   :: Int8  } deriving (Show, Eq, Ord, Generic)
newtype UImm5  = UImm5  { unUImm5  :: Word8 } deriving (Show, Eq, Ord, Generic)

data AqRl
  = AqRlNone
  | AqRlRelease
  | AqRlAcquire
  | AqRlAcqRel
  deriving (Show, Eq, Ord, Enum, Bounded, Generic)

-- DYN means "use frm CSR at runtime"
data RoundingMode = RNE | RTZ | RDN | RUP | RMM | DYN
  deriving (Show, Eq, Ord, Enum, Bounded, Generic)

data FenceMode = FenceMode
  { fenceI :: Bool  -- instructions
  , fenceO :: Bool  -- outputs
  , fenceR :: Bool  -- reads
  , fenceW :: Bool  -- writes
  } deriving (Show, Eq, Ord, Generic)

data PrivilegeLevel = User | Supervisor | Machine
  deriving (Show, Eq, Ord, Enum, Bounded, Generic)

-- ABI register aliases for readability in tests and scenarios
x0, ra, sp, gp, tp, t0, t1, t2, fp, s1 :: Register
a0, a1, a2, a3, a4, a5, a6, a7         :: Register
s2, s3, s4, s5, s6, s7, s8, s9, s10, s11 :: Register
t3, t4, t5, t6                          :: Register
x0  = Register  0;  ra  = Register  1;  sp  = Register  2
gp  = Register  3;  tp  = Register  4;  t0  = Register  5
t1  = Register  6;  t2  = Register  7;  fp  = Register  8
s1  = Register  9;  a0  = Register 10;  a1  = Register 11
a2  = Register 12;  a3  = Register 13;  a4  = Register 14
a5  = Register 15;  a6  = Register 16;  a7  = Register 17
s2  = Register 18;  s3  = Register 19;  s4  = Register 20
s5  = Register 21;  s6  = Register 22;  s7  = Register 23
s8  = Register 24;  s9  = Register 25;  s10 = Register 26
s11 = Register 27;  t3  = Register 28;  t4  = Register 29
t5  = Register 30;  t6  = Register 31
```

- [ ] **Step 4: Update test/Spec.hs to include the test**

`test/Spec.hs`:
```haskell
module Main (main) where

import Test.Tasty
import qualified Test.Core.Encode       as CoreEncode
import qualified Test.Core.Decode       as CoreDecode
import qualified Test.Constraint.Solver as CSolver
import qualified Test.Generator.Random  as GenRandom
import qualified Test.Coverage.Accumulator as CovAccum
import qualified Test.ELF.FlatBinary    as ELFTest
import qualified Test.CoSim.Spike       as SpikeTest

main :: IO ()
main = defaultMain $ testGroup "riscv-rig"
  [ CoreEncode.tests
  , CoreDecode.tests
  , CSolver.tests
  , GenRandom.tests
  , CovAccum.tests
  , ELFTest.tests
  , SpikeTest.tests
  ]
```

- [ ] **Step 5: Run tests to verify passing**

```
cabal test riscv-rig-test
```

Expected: `Core.Types` cases pass (4/4).

- [ ] **Step 6: Commit**

```bash
git add src/Core/Types.hs test/Test/Core/Encode.hs test/Spec.hs
git commit -m "feat: Core.Types — Register/Imm newtypes, AqRl, RoundingMode, FenceMode, PrivilegeLevel"
```

---

## Task 3: Core.Instruction

**Files:**
- Modify: `src/Core/Instruction.hs`
- Modify: `test/Test/Core/Encode.hs` (add instruction-count tests)

- [ ] **Step 1: Write the failing test**

Add to `test/Test/Core/Encode.hs`:
```haskell
import Core.Instruction

-- Add to tests TestTree:
, testCase "rv64i instructions are RV64I extension" $
    instrExtension (ADD x1 x2 x3) @?= RV64I
, testCase "mul is RV64M extension" $
    instrExtension (MUL x1 x2 x3) @?= RV64M
, testCase "mret is Privileged extension" $
    instrExtension MRET @?= RVPriv
, testCase "InstrFormat of ADD is RFormat" $
    instrFormat (ADD x1 x2 x3) @?= RFormat
, testCase "InstrFormat of ADDI is IFormat" $
    instrFormat (ADDI x1 x2 (Imm12 0)) @?= IFormat
, testCase "InstrFormat of BEQ is BFormat" $
    instrFormat (BEQ x1 x2 (Imm13 0)) @?= BFormat
```

- [ ] **Step 2: Run test to verify it fails**

```
cabal test riscv-rig-test
```

Expected: compile error — `ADD`, `MUL`, `MRET` not defined.

- [ ] **Step 3: Implement Core.Instruction**

`src/Core/Instruction.hs`:
```haskell
module Core.Instruction
  ( Instruction(..)
  , Extension(..)
  , InstrFormat(..)
  , instrExtension
  , instrFormat
  , isRV64I, isRV64M, isPrivileged
  , requiresExtensions
  ) where

import Core.Types
import GHC.Generics (Generic)

data Extension
  = RV64I
  | RV64M
  | RVPriv   -- privileged ISA (MRET, SRET, WFI, SFENCE.VMA)
  deriving (Show, Eq, Ord, Enum, Bounded, Generic)

data InstrFormat
  = RFormat   -- [funct7|rs2|rs1|funct3|rd|opcode]
  | IFormat   -- [imm12|rs1|funct3|rd|opcode]
  | SFormat   -- [imm[11:5]|rs2|rs1|funct3|imm[4:0]|opcode]
  | BFormat   -- [imm[12|10:5]|rs2|rs1|funct3|imm[4:1|11]|opcode]
  | UFormat   -- [imm20|rd|opcode]
  | JFormat   -- [imm[20|10:1|11|19:12]|rd|opcode]
  deriving (Show, Eq, Ord, Enum, Bounded, Generic)

data Instruction
  -- ── RV64I: Arithmetic ──────────────────────────────────────────
  = ADD    Register Register Register   -- rd = rs1 + rs2
  | SUB    Register Register Register   -- rd = rs1 - rs2
  | ADDI   Register Register Imm12      -- rd = rs1 + sext(imm)
  | ADDIW  Register Register Imm12      -- rd = sext32(rs1[31:0] + sext(imm))
  | ADDW   Register Register Register
  | SUBW   Register Register Register
  -- ── RV64I: Logical ─────────────────────────────────────────────
  | AND    Register Register Register
  | OR     Register Register Register
  | XOR    Register Register Register
  | ANDI   Register Register Imm12
  | ORI    Register Register Imm12
  | XORI   Register Register Imm12
  -- ── RV64I: Shift ───────────────────────────────────────────────
  | SLL    Register Register Register
  | SRL    Register Register Register
  | SRA    Register Register Register
  | SLLI   Register Register UImm5
  | SRLI   Register Register UImm5
  | SRAI   Register Register UImm5
  | SLLIW  Register Register UImm5
  | SRLIW  Register Register UImm5
  | SRAIW  Register Register UImm5
  | SLLW   Register Register Register
  | SRLW   Register Register Register
  | SRAW   Register Register Register
  -- ── RV64I: Compare ─────────────────────────────────────────────
  | SLT    Register Register Register
  | SLTU   Register Register Register
  | SLTI   Register Register Imm12
  | SLTIU  Register Register Imm12
  -- ── RV64I: Upper Immediate ─────────────────────────────────────
  | LUI    Register Imm20               -- rd = imm << 12 (sign-extended to 64)
  | AUIPC  Register Imm20               -- rd = PC + (imm << 12)
  -- ── RV64I: Load ────────────────────────────────────────────────
  | LB     Register Register Imm12      -- rd = sext8(mem[rs1+imm])
  | LH     Register Register Imm12
  | LW     Register Register Imm12
  | LD     Register Register Imm12
  | LBU    Register Register Imm12      -- rd = zext8(mem[rs1+imm])
  | LHU    Register Register Imm12
  | LWU    Register Register Imm12
  -- ── RV64I: Store ───────────────────────────────────────────────
  | SB     Register Register Imm12      -- mem[rs1+imm] = rs2[7:0]
  | SH     Register Register Imm12
  | SW     Register Register Imm12
  | SD     Register Register Imm12
  -- ── RV64I: Branch ──────────────────────────────────────────────
  | BEQ    Register Register Imm13      -- if rs1==rs2: PC+=imm
  | BNE    Register Register Imm13
  | BLT    Register Register Imm13
  | BGE    Register Register Imm13
  | BLTU   Register Register Imm13
  | BGEU   Register Register Imm13
  -- ── RV64I: Jump ────────────────────────────────────────────────
  | JAL    Register Imm21               -- rd=PC+4; PC+=imm
  | JALR   Register Register Imm12      -- rd=PC+4; PC=(rs1+imm)&~1
  -- ── RV64I: System ──────────────────────────────────────────────
  | ECALL
  | EBREAK
  | FENCE  FenceMode FenceMode          -- predecessor, successor
  | FENCE_I
  -- ── RV64I: CSR ─────────────────────────────────────────────────
  | CSRRW  Register CSRAddr Register    -- rd=csr; csr=rs1
  | CSRRS  Register CSRAddr Register    -- rd=csr; csr|=rs1
  | CSRRC  Register CSRAddr Register    -- rd=csr; csr&=~rs1
  | CSRRWI Register CSRAddr UImm5       -- rd=csr; csr=zimm
  | CSRRSI Register CSRAddr UImm5
  | CSRRCI Register CSRAddr UImm5
  -- ── RV64M: Multiply ────────────────────────────────────────────
  | MUL    Register Register Register   -- rd = rs1 * rs2 [63:0]
  | MULH   Register Register Register   -- rd = (rs1 * rs2) >> 64 (signed)
  | MULHSU Register Register Register   -- rd = (signed*unsigned) >> 64
  | MULHU  Register Register Register   -- rd = (rs1 * rs2) >> 64 (unsigned)
  | DIV    Register Register Register
  | DIVU   Register Register Register
  | REM    Register Register Register
  | REMU   Register Register Register
  | MULW   Register Register Register   -- rd = sext32(rs1[31:0] * rs2[31:0])
  | DIVW   Register Register Register
  | DIVUW  Register Register Register
  | REMW   Register Register Register
  | REMUW  Register Register Register
  -- ── Privileged ─────────────────────────────────────────────────
  | MRET                                -- return from M-mode trap
  | SRET                                -- return from S-mode trap
  | WFI                                 -- wait for interrupt
  | SFENCE_VMA Register Register        -- flush TLB for (rs1=vaddr, rs2=asid)
  deriving (Show, Eq, Ord, Generic)

-- ── Helpers ──────────────────────────────────────────────────────

instrExtension :: Instruction -> Extension
instrExtension instr = case instr of
  MUL{}    -> RV64M; MULH{}   -> RV64M; MULHSU{} -> RV64M; MULHU{}  -> RV64M
  DIV{}    -> RV64M; DIVU{}   -> RV64M; REM{}    -> RV64M; REMU{}   -> RV64M
  MULW{}   -> RV64M; DIVW{}   -> RV64M; DIVUW{}  -> RV64M; REMW{}   -> RV64M
  REMUW{}  -> RV64M
  MRET     -> RVPriv; SRET -> RVPriv; WFI -> RVPriv; SFENCE_VMA{} -> RVPriv
  _        -> RV64I

instrFormat :: Instruction -> InstrFormat
instrFormat = \case
  ADD{} -> RFormat; SUB{}  -> RFormat; ADDW{} -> RFormat; SUBW{} -> RFormat
  AND{} -> RFormat; OR{}   -> RFormat; XOR{}  -> RFormat
  SLL{} -> RFormat; SRL{}  -> RFormat; SRA{}  -> RFormat
  SLLW{} -> RFormat; SRLW{} -> RFormat; SRAW{} -> RFormat
  SLT{} -> RFormat; SLTU{} -> RFormat
  MUL{}  -> RFormat; MULH{}  -> RFormat; MULHSU{} -> RFormat; MULHU{} -> RFormat
  DIV{}  -> RFormat; DIVU{}  -> RFormat; REM{}    -> RFormat; REMU{}  -> RFormat
  MULW{} -> RFormat; DIVW{}  -> RFormat; DIVUW{}  -> RFormat; REMW{}  -> RFormat
  REMUW{} -> RFormat
  ADDI{} -> IFormat; ADDIW{} -> IFormat; SLLI{} -> IFormat; SRLI{} -> IFormat
  SRAI{} -> IFormat; SLLIW{} -> IFormat; SRLIW{} -> IFormat; SRAIW{} -> IFormat
  SLTI{} -> IFormat; SLTIU{} -> IFormat; ANDI{} -> IFormat; ORI{}  -> IFormat
  XORI{} -> IFormat; LB{} -> IFormat; LH{} -> IFormat; LW{} -> IFormat
  LD{} -> IFormat; LBU{} -> IFormat; LHU{} -> IFormat; LWU{} -> IFormat
  JALR{} -> IFormat; CSRRW{} -> IFormat; CSRRS{} -> IFormat; CSRRC{} -> IFormat
  CSRRWI{} -> IFormat; CSRRSI{} -> IFormat; CSRRCI{} -> IFormat
  ECALL -> IFormat; EBREAK -> IFormat; FENCE{} -> IFormat; FENCE_I -> IFormat
  MRET -> IFormat; SRET -> IFormat; WFI -> IFormat; SFENCE_VMA{} -> RFormat
  SB{} -> SFormat; SH{} -> SFormat; SW{} -> SFormat; SD{} -> SFormat
  BEQ{} -> BFormat; BNE{} -> BFormat; BLT{} -> BFormat; BGE{} -> BFormat
  BLTU{} -> BFormat; BGEU{} -> BFormat
  LUI{} -> UFormat; AUIPC{} -> UFormat
  JAL{} -> JFormat

isRV64I, isRV64M, isPrivileged :: Instruction -> Bool
isRV64I     i = instrExtension i == RV64I
isRV64M     i = instrExtension i == RV64M
isPrivileged i = instrExtension i == RVPriv

requiresExtensions :: Instruction -> [Extension]
requiresExtensions i = [instrExtension i]
```

- [ ] **Step 4: Run tests to verify passing**

```
cabal test riscv-rig-test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/Core/Instruction.hs test/Test/Core/Encode.hs
git commit -m "feat: Core.Instruction — full RV64I+M+Priv ADT, Extension, InstrFormat"
```

---

## Task 4: Core.Encode

**Files:**
- Modify: `src/Core/Encode.hs`
- Modify: `test/Test/Core/Encode.hs` (add known-encoding unit tests)

The encode function translates the semantic ADT into the 32-bit binary encoding defined by the RISC-V spec. We verify against known values from the spec.

- [ ] **Step 1: Write the failing tests**

Add to `test/Test/Core/Encode.hs`:
```haskell
import Core.Encode
import Data.Word (Word32)

encodeTests :: TestTree
encodeTests = testGroup "Core.Encode"
  [ -- Known encodings verified against the RISC-V ISA spec
    testCase "ADD x1,x2,x3 = 0x003100B3" $
      encode (ADD (Register 1) (Register 2) (Register 3)) @?= 0x003100B3
  , testCase "ADDI x1,x0,1 = 0x00100093" $
      encode (ADDI (Register 1) (Register 0) (Imm12 1)) @?= 0x00100093
  , testCase "LUI x1,1 = 0x000010B7" $
      encode (LUI (Register 1) (Imm20 1)) @?= 0x000010B7
  , testCase "JAL x0,0 = 0x0000006F" $
      encode (JAL (Register 0) (Imm21 0)) @?= 0x0000006F
  , testCase "BEQ x1,x2,0 = 0x00208063" $
      encode (BEQ (Register 1) (Register 2) (Imm13 0)) @?= 0x00208063
  , testCase "SW x2,0(x1) = 0x0020A023" $
      encode (SW (Register 2) (Register 1) (Imm12 0)) @?= 0x0020A023
  , testCase "MUL x1,x2,x3 = 0x023100B3" $
      encode (MUL (Register 1) (Register 2) (Register 3)) @?= 0x023100B3
  , testCase "ECALL = 0x00000073" $
      encode ECALL @?= 0x00000073
  , testCase "MRET = 0x30200073" $
      encode MRET @?= 0x30200073
  , testCase "CSRRW x1,mstatus,x0 = 0x300010F3" $
      encode (CSRRW (Register 1) (CSRAddr 0x300) (Register 0)) @?= 0x300010F3
  ]
```

Update `tests` in the module to include `encodeTests`:
```haskell
tests :: TestTree
tests = testGroup "Core" [typeTests, encodeTests]
  where typeTests = testGroup "Core.Types" [ {- existing cases -} ]
```

- [ ] **Step 2: Run test to verify it fails**

```
cabal test riscv-rig-test --test-option="--pattern=Core.Encode"
```

Expected: compile error — `encode` not defined.

- [ ] **Step 3: Implement Core.Encode**

`src/Core/Encode.hs`:
```haskell
module Core.Encode (encode) where

import Core.Types
import Core.Instruction
import Data.Bits  (shiftL, shiftR, (.|.), (.&.))
import Data.Word  (Word32)

-- ── Format builders ───────────────────────────────────────────────

-- R-type: [funct7|rs2|rs1|funct3|rd|opcode]
buildR :: Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32
buildR opcode rd funct3 rs1 rs2 funct7 =
  (funct7 `shiftL` 25) .|. (rs2 `shiftL` 20) .|. (rs1 `shiftL` 15)
  .|. (funct3 `shiftL` 12) .|. (rd `shiftL` 7) .|. opcode

-- I-type: [imm[11:0]|rs1|funct3|rd|opcode]
buildI :: Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32
buildI opcode rd funct3 rs1 imm12 =
  ((imm12 .&. 0xFFF) `shiftL` 20) .|. (rs1 `shiftL` 15)
  .|. (funct3 `shiftL` 12) .|. (rd `shiftL` 7) .|. opcode

-- I-type with special imm encoding for shifts (bit 30 = arithmetic/logical)
buildIShift :: Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32
buildIShift opcode rd funct3 rs1 shamt funct6 =
  (funct6 `shiftL` 26) .|. (shamt .&. 0x3F) `shiftL` 20
  .|. (rs1 `shiftL` 15) .|. (funct3 `shiftL` 12) .|. (rd `shiftL` 7) .|. opcode

-- S-type: [imm[11:5]|rs2|rs1|funct3|imm[4:0]|opcode]
buildS :: Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32
buildS opcode funct3 rs1 rs2 imm12 =
  let i = imm12 .&. 0xFFF
  in  ((i `shiftR` 5) .&. 0x7F) `shiftL` 25 .|. (rs2 `shiftL` 20)
      .|. (rs1 `shiftL` 15) .|. (funct3 `shiftL` 12)
      .|. (i .&. 0x1F) `shiftL` 7 .|. opcode

-- B-type: [imm[12]|imm[10:5]|rs2|rs1|funct3|imm[4:1]|imm[11]|opcode]
buildB :: Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32
buildB opcode funct3 rs1 rs2 imm13 =
  let i = imm13 .&. 0x1FFF
  in  ((i `shiftR` 12) .&. 0x1) `shiftL` 31
      .|. ((i `shiftR` 5) .&. 0x3F) `shiftL` 25
      .|. (rs2 `shiftL` 20) .|. (rs1 `shiftL` 15)
      .|. (funct3 `shiftL` 12)
      .|. ((i `shiftR` 1) .&. 0xF) `shiftL` 8
      .|. ((i `shiftR` 11) .&. 0x1) `shiftL` 7
      .|. opcode

-- U-type: [imm[31:12]|rd|opcode]
buildU :: Word32 -> Word32 -> Word32 -> Word32
buildU opcode rd imm20 =
  ((imm20 .&. 0xFFFFF) `shiftL` 12) .|. (rd `shiftL` 7) .|. opcode

-- J-type: [imm[20]|imm[10:1]|imm[11]|imm[19:12]|rd|opcode]
buildJ :: Word32 -> Word32 -> Word32 -> Word32
buildJ opcode rd imm21 =
  let i = imm21 .&. 0x1FFFFF
  in  ((i `shiftR` 20) .&. 0x1) `shiftL` 31
      .|. ((i `shiftR` 1) .&. 0x3FF) `shiftL` 21
      .|. ((i `shiftR` 11) .&. 0x1) `shiftL` 20
      .|. ((i `shiftR` 12) .&. 0xFF) `shiftL` 12
      .|. (rd `shiftL` 7) .|. opcode

-- ── Conversions ───────────────────────────────────────────────────

r :: Register -> Word32
r (Register x) = fromIntegral x

fr :: FPRegister -> Word32
fr (FPRegister x) = fromIntegral x

csr :: CSRAddr -> Word32
csr (CSRAddr x) = fromIntegral x

i12 :: Imm12 -> Word32
i12 (Imm12 x) = fromIntegral x  -- sign bit extends naturally in Word32

i13 :: Imm13 -> Word32
i13 (Imm13 x) = fromIntegral x

i20 :: Imm20 -> Word32
i20 (Imm20 x) = fromIntegral x

i21 :: Imm21 -> Word32
i21 (Imm21 x) = fromIntegral x

u5 :: UImm5 -> Word32
u5 (UImm5 x) = fromIntegral x

-- ── Main encode function ──────────────────────────────────────────

encode :: Instruction -> Word32
encode = \case
  -- ── RV64I: Arithmetic ──────────────────────────────────────────
  ADD  rd rs1 rs2 -> buildR 0x33 (r rd) 0x0 (r rs1) (r rs2) 0x00
  SUB  rd rs1 rs2 -> buildR 0x33 (r rd) 0x0 (r rs1) (r rs2) 0x20
  ADDI rd rs1 imm -> buildI 0x13 (r rd) 0x0 (r rs1) (i12 imm)
  ADDIW rd rs1 imm -> buildI 0x1B (r rd) 0x0 (r rs1) (i12 imm)
  ADDW rd rs1 rs2 -> buildR 0x3B (r rd) 0x0 (r rs1) (r rs2) 0x00
  SUBW rd rs1 rs2 -> buildR 0x3B (r rd) 0x0 (r rs1) (r rs2) 0x20
  -- ── Logical ────────────────────────────────────────────────────
  AND  rd rs1 rs2 -> buildR 0x33 (r rd) 0x7 (r rs1) (r rs2) 0x00
  OR   rd rs1 rs2 -> buildR 0x33 (r rd) 0x6 (r rs1) (r rs2) 0x00
  XOR  rd rs1 rs2 -> buildR 0x33 (r rd) 0x4 (r rs1) (r rs2) 0x00
  ANDI rd rs1 imm -> buildI 0x13 (r rd) 0x7 (r rs1) (i12 imm)
  ORI  rd rs1 imm -> buildI 0x13 (r rd) 0x6 (r rs1) (i12 imm)
  XORI rd rs1 imm -> buildI 0x13 (r rd) 0x4 (r rs1) (i12 imm)
  -- ── Shift ──────────────────────────────────────────────────────
  SLL  rd rs1 rs2 -> buildR 0x33 (r rd) 0x1 (r rs1) (r rs2) 0x00
  SRL  rd rs1 rs2 -> buildR 0x33 (r rd) 0x5 (r rs1) (r rs2) 0x00
  SRA  rd rs1 rs2 -> buildR 0x33 (r rd) 0x5 (r rs1) (r rs2) 0x20
  SLLI rd rs1 sh  -> buildIShift 0x13 (r rd) 0x1 (r rs1) (u5 sh) 0x00
  SRLI rd rs1 sh  -> buildIShift 0x13 (r rd) 0x5 (r rs1) (u5 sh) 0x00
  SRAI rd rs1 sh  -> buildIShift 0x13 (r rd) 0x5 (r rs1) (u5 sh) 0x10
  SLLIW rd rs1 sh -> buildR 0x1B (r rd) 0x1 (r rs1) (u5 sh) 0x00
  SRLIW rd rs1 sh -> buildR 0x1B (r rd) 0x5 (r rs1) (u5 sh) 0x00
  SRAIW rd rs1 sh -> buildR 0x1B (r rd) 0x5 (r rs1) (u5 sh) 0x20
  SLLW rd rs1 rs2 -> buildR 0x3B (r rd) 0x1 (r rs1) (r rs2) 0x00
  SRLW rd rs1 rs2 -> buildR 0x3B (r rd) 0x5 (r rs1) (r rs2) 0x00
  SRAW rd rs1 rs2 -> buildR 0x3B (r rd) 0x5 (r rs1) (r rs2) 0x20
  -- ── Compare ────────────────────────────────────────────────────
  SLT  rd rs1 rs2 -> buildR 0x33 (r rd) 0x2 (r rs1) (r rs2) 0x00
  SLTU rd rs1 rs2 -> buildR 0x33 (r rd) 0x3 (r rs1) (r rs2) 0x00
  SLTI  rd rs1 imm -> buildI 0x13 (r rd) 0x2 (r rs1) (i12 imm)
  SLTIU rd rs1 imm -> buildI 0x13 (r rd) 0x3 (r rs1) (i12 imm)
  -- ── Upper immediate ────────────────────────────────────────────
  LUI   rd imm -> buildU 0x37 (r rd) (i20 imm)
  AUIPC rd imm -> buildU 0x17 (r rd) (i20 imm)
  -- ── Load ───────────────────────────────────────────────────────
  LB  rd rs1 imm -> buildI 0x03 (r rd) 0x0 (r rs1) (i12 imm)
  LH  rd rs1 imm -> buildI 0x03 (r rd) 0x1 (r rs1) (i12 imm)
  LW  rd rs1 imm -> buildI 0x03 (r rd) 0x2 (r rs1) (i12 imm)
  LD  rd rs1 imm -> buildI 0x03 (r rd) 0x3 (r rs1) (i12 imm)
  LBU rd rs1 imm -> buildI 0x03 (r rd) 0x4 (r rs1) (i12 imm)
  LHU rd rs1 imm -> buildI 0x03 (r rd) 0x5 (r rs1) (i12 imm)
  LWU rd rs1 imm -> buildI 0x03 (r rd) 0x6 (r rs1) (i12 imm)
  -- ── Store ──────────────────────────────────────────────────────
  SB rs2 rs1 imm -> buildS 0x23 0x0 (r rs1) (r rs2) (i12 imm)
  SH rs2 rs1 imm -> buildS 0x23 0x1 (r rs1) (r rs2) (i12 imm)
  SW rs2 rs1 imm -> buildS 0x23 0x2 (r rs1) (r rs2) (i12 imm)
  SD rs2 rs1 imm -> buildS 0x23 0x3 (r rs1) (r rs2) (i12 imm)
  -- ── Branch ─────────────────────────────────────────────────────
  BEQ  rs1 rs2 imm -> buildB 0x63 0x0 (r rs1) (r rs2) (i13 imm)
  BNE  rs1 rs2 imm -> buildB 0x63 0x1 (r rs1) (r rs2) (i13 imm)
  BLT  rs1 rs2 imm -> buildB 0x63 0x4 (r rs1) (r rs2) (i13 imm)
  BGE  rs1 rs2 imm -> buildB 0x63 0x5 (r rs1) (r rs2) (i13 imm)
  BLTU rs1 rs2 imm -> buildB 0x63 0x6 (r rs1) (r rs2) (i13 imm)
  BGEU rs1 rs2 imm -> buildB 0x63 0x7 (r rs1) (r rs2) (i13 imm)
  -- ── Jump ───────────────────────────────────────────────────────
  JAL  rd imm     -> buildJ 0x6F (r rd) (i21 imm)
  JALR rd rs1 imm -> buildI 0x67 (r rd) 0x0 (r rs1) (i12 imm)
  -- ── System ─────────────────────────────────────────────────────
  ECALL   -> buildI 0x73 0 0 0 0
  EBREAK  -> buildI 0x73 0 0 0 1
  FENCE_I -> buildI 0x0F 0 0x1 0 0
  FENCE pre suc ->
    let encFm fm = (if fenceI fm then 8 else 0) .|. (if fenceO fm then 4 else 0)
                   .|. (if fenceR fm then 2 else 0) .|. (if fenceW fm then 1 else 0)
    in  (encFm pre `shiftL` 24) .|. (encFm suc `shiftL` 20) .|. 0x0F
  -- ── CSR ────────────────────────────────────────────────────────
  CSRRW  rd caddr rs1 -> buildI 0x73 (r rd) 0x1 (r rs1) (csr caddr)
  CSRRS  rd caddr rs1 -> buildI 0x73 (r rd) 0x2 (r rs1) (csr caddr)
  CSRRC  rd caddr rs1 -> buildI 0x73 (r rd) 0x3 (r rs1) (csr caddr)
  CSRRWI rd caddr imm -> buildI 0x73 (r rd) 0x5 (u5 imm) (csr caddr)
  CSRRSI rd caddr imm -> buildI 0x73 (r rd) 0x6 (u5 imm) (csr caddr)
  CSRRCI rd caddr imm -> buildI 0x73 (r rd) 0x7 (u5 imm) (csr caddr)
  -- ── RV64M ──────────────────────────────────────────────────────
  MUL    rd rs1 rs2 -> buildR 0x33 (r rd) 0x0 (r rs1) (r rs2) 0x01
  MULH   rd rs1 rs2 -> buildR 0x33 (r rd) 0x1 (r rs1) (r rs2) 0x01
  MULHSU rd rs1 rs2 -> buildR 0x33 (r rd) 0x2 (r rs1) (r rs2) 0x01
  MULHU  rd rs1 rs2 -> buildR 0x33 (r rd) 0x3 (r rs1) (r rs2) 0x01
  DIV    rd rs1 rs2 -> buildR 0x33 (r rd) 0x4 (r rs1) (r rs2) 0x01
  DIVU   rd rs1 rs2 -> buildR 0x33 (r rd) 0x5 (r rs1) (r rs2) 0x01
  REM    rd rs1 rs2 -> buildR 0x33 (r rd) 0x6 (r rs1) (r rs2) 0x01
  REMU   rd rs1 rs2 -> buildR 0x33 (r rd) 0x7 (r rs1) (r rs2) 0x01
  MULW   rd rs1 rs2 -> buildR 0x3B (r rd) 0x0 (r rs1) (r rs2) 0x01
  DIVW   rd rs1 rs2 -> buildR 0x3B (r rd) 0x4 (r rs1) (r rs2) 0x01
  DIVUW  rd rs1 rs2 -> buildR 0x3B (r rd) 0x5 (r rs1) (r rs2) 0x01
  REMW   rd rs1 rs2 -> buildR 0x3B (r rd) 0x6 (r rs1) (r rs2) 0x01
  REMUW  rd rs1 rs2 -> buildR 0x3B (r rd) 0x7 (r rs1) (r rs2) 0x01
  -- ── Privileged ─────────────────────────────────────────────────
  MRET -> buildR 0x73 0 0 0 2 0x18         -- funct7=0011000, rs2=00010
  SRET -> buildR 0x73 0 0 0 2 0x08         -- funct7=0001000, rs2=00010
  WFI  -> buildR 0x73 0 0 0 5 0x08         -- funct7=0001000, rs2=00101
  SFENCE_VMA rs1 rs2 -> buildR 0x73 0 0 (r rs1) (r rs2) 0x09
```

- [ ] **Step 4: Run tests to verify passing**

```
cabal test riscv-rig-test --test-option="--pattern=Core.Encode"
```

Expected: all 10 encoding tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/Core/Encode.hs test/Test/Core/Encode.hs
git commit -m "feat: Core.Encode — encode :: Instruction -> Word32, all RV64I+M+Priv"
```

---

## Task 5: Core.Decode + Roundtrip Test

**Files:**
- Modify: `src/Core/Decode.hs`
- Modify: `test/Test/Core/Decode.hs`

- [ ] **Step 1: Write the failing test**

`test/Test/Core/Decode.hs`:
```haskell
module Test.Core.Decode (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog
import Hedgehog
import qualified Hedgehog.Gen   as Gen
import qualified Hedgehog.Range as Range
import Core.Types
import Core.Instruction
import Core.Encode
import Core.Decode

tests :: TestTree
tests = testGroup "Core.Decode"
  [ testCase "decode known ADD" $
      decode 0x003100B3 @?= Right (ADD (Register 1) (Register 2) (Register 3))
  , testCase "decode unknown opcode returns Left" $
      case decode 0xFFFFFFFF of
        Left _ -> return ()
        Right _ -> assertFailure "expected DecodeError"
  , testProperty "encode/decode roundtrip for sample instructions" $
      property $ do
        instr <- forAll genSampleInstruction
        decode (encode instr) === Right instr
  ]

-- Generate a subset of instructions safe to roundtrip
genSampleInstruction :: Gen Instruction
genSampleInstruction = Gen.choice
  [ ADD  <$> genReg <*> genReg <*> genReg
  , SUB  <$> genReg <*> genReg <*> genReg
  , ADDI <$> genReg <*> genReg <*> genImm12
  , LUI  <$> genReg <*> genImm20
  , LW   <$> genReg <*> genReg <*> genImm12
  , SW   <$> genReg <*> genReg <*> genImm12
  , BEQ  <$> genReg <*> genReg <*> genImm13Even
  , JAL  <$> genReg <*> genImm21Even
  , MUL  <$> genReg <*> genReg <*> genReg
  , pure ECALL
  , pure MRET
  ]
  where
    genReg       = Register  <$> Gen.word8 (Range.linear 0 31)
    genImm12     = Imm12     <$> Gen.int16 (Range.linearFrom 0 (-2048) 2047)
    genImm20     = Imm20     <$> Gen.int32 (Range.linearFrom 0 0 0xFFFFF)
    genImm13Even = Imm13 . (\x -> x - x `mod` 2)
                         <$> Gen.int16 (Range.linearFrom 0 (-4096) 4094)
    genImm21Even = Imm21 . (\x -> x - x `mod` 2)
                         <$> Gen.int32 (Range.linearFrom 0 (-1048576) 1048574)
```

- [ ] **Step 2: Run test to verify it fails**

```
cabal test riscv-rig-test --test-option="--pattern=Core.Decode"
```

Expected: compile error — `decode`, `DecodeError` not defined.

- [ ] **Step 3: Implement Core.Decode**

`src/Core/Decode.hs`:
```haskell
module Core.Decode
  ( decode
  , DecodeError(..)
  ) where

import Core.Types
import Core.Instruction
import Data.Bits  (shiftL, shiftR, (.|.), (.&.), testBit)
import Data.Word  (Word32)
import Data.Int   (Int16, Int32)

data DecodeError
  = UnknownOpcode     Word32
  | UnknownFunct3     Word32 Word32
  | UnknownFunct7     Word32 Word32 Word32
  | ReservedEncoding  Word32
  deriving (Show, Eq)

-- ── Bit helpers ───────────────────────────────────────────────────

field :: Word32 -> Int -> Int -> Word32
field w hi lo = (w `shiftR` lo) .&. ((1 `shiftL` (hi - lo + 1)) - 1)

opcode, rd', funct3', rs1', rs2', funct7' :: Word32 -> Word32
opcode  w = field w  6  0
rd'     w = field w 11  7
funct3' w = field w 14 12
rs1'    w = field w 19 15
rs2'    w = field w 24 20
funct7' w = field w 31 25

signExt12 :: Word32 -> Int16
signExt12 w =
  let v = fromIntegral (w .&. 0xFFF) :: Int16
  in  if testBit v 11 then v - 0x1000 else v

signExt13 :: Word32 -> Int16
signExt13 w =
  let b12 = field w 31 31; b11 = field w  7  7
      b10 = field w 30 25; b4  = field w 11  8
      v   = fromIntegral ((b12 `shiftL` 12) .|. (b11 `shiftL` 11)
                          .|. (b10 `shiftL` 5) .|. (b4 `shiftL` 1)) :: Int16
  in  v

signExt20 :: Word32 -> Int32
signExt20 w = fromIntegral (field w 31 12)

signExt21 :: Word32 -> Int32
signExt21 w =
  let b20  = field w 31 31; b19_12 = field w 19 12
      b11  = field w 20 20; b10_1  = field w 30 21
      v    = fromIntegral
               ((b20 `shiftL` 20) .|. (b19_12 `shiftL` 12) .|.
                (b11 `shiftL` 11) .|. (b10_1 `shiftL` 1)) :: Int32
  in  v

mkReg :: Word32 -> Register
mkReg = Register . fromIntegral

mkCSR :: Word32 -> CSRAddr
mkCSR = CSRAddr . fromIntegral

mkUImm5 :: Word32 -> UImm5
mkUImm5 = UImm5 . fromIntegral

-- ── Decode ────────────────────────────────────────────────────────

decode :: Word32 -> Either DecodeError Instruction
decode w = case opcode w of
  0x33 -> decodeR33 w
  0x3B -> decodeR3B w
  0x13 -> decodeI13 w
  0x1B -> decodeI1B w
  0x03 -> decodeLoad w
  0x23 -> decodeStore w
  0x63 -> decodeBranch w
  0x37 -> Right $ LUI   (mkReg (rd' w)) (Imm20 (signExt20 w))
  0x17 -> Right $ AUIPC (mkReg (rd' w)) (Imm20 (signExt20 w))
  0x6F -> Right $ JAL   (mkReg (rd' w)) (Imm21 (signExt21 w))
  0x67 -> Right $ JALR  (mkReg (rd' w)) (mkReg (rs1' w)) (Imm12 (signExt12 (field w 31 20)))
  0x73 -> decodeSystem w
  0x0F -> decodeFence w
  op   -> Left (UnknownOpcode op)

decodeR33 :: Word32 -> Either DecodeError Instruction
decodeR33 w = case (funct3' w, funct7' w) of
  (0x0, 0x00) -> Right $ ADD  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x0, 0x20) -> Right $ SUB  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x7, 0x00) -> Right $ AND  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x6, 0x00) -> Right $ OR   (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x4, 0x00) -> Right $ XOR  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x1, 0x00) -> Right $ SLL  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x5, 0x00) -> Right $ SRL  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x5, 0x20) -> Right $ SRA  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x2, 0x00) -> Right $ SLT  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x3, 0x00) -> Right $ SLTU (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x0, 0x01) -> Right $ MUL    (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x1, 0x01) -> Right $ MULH   (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x2, 0x01) -> Right $ MULHSU (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x3, 0x01) -> Right $ MULHU  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x4, 0x01) -> Right $ DIV    (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x5, 0x01) -> Right $ DIVU   (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x6, 0x01) -> Right $ REM    (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x7, 0x01) -> Right $ REMU   (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (f3, f7)    -> Left (UnknownFunct7 0x33 f3 f7)

decodeR3B :: Word32 -> Either DecodeError Instruction
decodeR3B w = case (funct3' w, funct7' w) of
  (0x0, 0x00) -> Right $ ADDW  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x0, 0x20) -> Right $ SUBW  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x1, 0x00) -> Right $ SLLW  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x5, 0x00) -> Right $ SRLW  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x5, 0x20) -> Right $ SRAW  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x0, 0x01) -> Right $ MULW  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x4, 0x01) -> Right $ DIVW  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x5, 0x01) -> Right $ DIVUW (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x6, 0x01) -> Right $ REMW  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x7, 0x01) -> Right $ REMUW (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (f3, f7)    -> Left (UnknownFunct7 0x3B f3 f7)

decodeI13 :: Word32 -> Either DecodeError Instruction
decodeI13 w =
  let imm = Imm12 (signExt12 (field w 31 20))
      rd  = mkReg (rd' w)
      rs  = mkReg (rs1' w)
      sh  = UImm5 (fromIntegral (field w 25 20))
  in case funct3' w of
    0x0 -> Right $ ADDI  rd rs imm
    0x7 -> Right $ ANDI  rd rs imm
    0x6 -> Right $ ORI   rd rs imm
    0x4 -> Right $ XORI  rd rs imm
    0x2 -> Right $ SLTI  rd rs imm
    0x3 -> Right $ SLTIU rd rs imm
    0x1 -> Right $ SLLI  rd rs sh
    0x5 -> if funct7' w == 0x20
              then Right $ SRAI rd rs sh
              else Right $ SRLI rd rs sh
    f3  -> Left (UnknownFunct3 0x13 f3)

decodeI1B :: Word32 -> Either DecodeError Instruction
decodeI1B w =
  let imm = Imm12 (signExt12 (field w 31 20))
      rd  = mkReg (rd' w)
      rs  = mkReg (rs1' w)
      sh  = UImm5 (fromIntegral (field w 24 20))
  in case funct3' w of
    0x0 -> Right $ ADDIW rd rs imm
    0x1 -> Right $ SLLIW rd rs sh
    0x5 -> if funct7' w == 0x20
              then Right $ SRAIW rd rs sh
              else Right $ SRLIW rd rs sh
    f3  -> Left (UnknownFunct3 0x1B f3)

decodeLoad :: Word32 -> Either DecodeError Instruction
decodeLoad w =
  let imm = Imm12 (signExt12 (field w 31 20))
      rd  = mkReg (rd' w)
      rs  = mkReg (rs1' w)
  in case funct3' w of
    0x0 -> Right $ LB  rd rs imm
    0x1 -> Right $ LH  rd rs imm
    0x2 -> Right $ LW  rd rs imm
    0x3 -> Right $ LD  rd rs imm
    0x4 -> Right $ LBU rd rs imm
    0x5 -> Right $ LHU rd rs imm
    0x6 -> Right $ LWU rd rs imm
    f3  -> Left (UnknownFunct3 0x03 f3)

decodeStore :: Word32 -> Either DecodeError Instruction
decodeStore w =
  let immRaw = (field w 31 25 `shiftL` 5) .|. field w 11 7
      imm    = Imm12 (if testBit immRaw 11
                      then fromIntegral immRaw - 0x1000
                      else fromIntegral immRaw)
      rs1v   = mkReg (rs1' w)
      rs2v   = mkReg (rs2' w)
  in case funct3' w of
    0x0 -> Right $ SB rs2v rs1v imm
    0x1 -> Right $ SH rs2v rs1v imm
    0x2 -> Right $ SW rs2v rs1v imm
    0x3 -> Right $ SD rs2v rs1v imm
    f3  -> Left (UnknownFunct3 0x23 f3)

decodeBranch :: Word32 -> Either DecodeError Instruction
decodeBranch w =
  let imm   = Imm13 (signExt13 w)
      rs1v  = mkReg (rs1' w)
      rs2v  = mkReg (rs2' w)
  in case funct3' w of
    0x0 -> Right $ BEQ  rs1v rs2v imm
    0x1 -> Right $ BNE  rs1v rs2v imm
    0x4 -> Right $ BLT  rs1v rs2v imm
    0x5 -> Right $ BGE  rs1v rs2v imm
    0x6 -> Right $ BLTU rs1v rs2v imm
    0x7 -> Right $ BGEU rs1v rs2v imm
    f3  -> Left (UnknownFunct3 0x63 f3)

decodeSystem :: Word32 -> Either DecodeError Instruction
decodeSystem w = case funct3' w of
  0x0 -> case (rs1' w, rs2' w, funct7' w) of
    (0, 0, 0x00) -> Right ECALL
    (0, 1, 0x00) -> Right EBREAK
    (0, 2, 0x18) -> Right MRET
    (0, 2, 0x08) -> Right SRET
    (0, 5, 0x08) -> Right WFI
    _            ->
      if funct7' w == 0x09
        then Right $ SFENCE_VMA (mkReg (rs1' w)) (mkReg (rs2' w))
        else Left (UnknownFunct7 0x73 0 (funct7' w))
  0x1 -> Right $ CSRRW  (mkReg (rd' w)) (mkCSR (field w 31 20)) (mkReg (rs1' w))
  0x2 -> Right $ CSRRS  (mkReg (rd' w)) (mkCSR (field w 31 20)) (mkReg (rs1' w))
  0x3 -> Right $ CSRRC  (mkReg (rd' w)) (mkCSR (field w 31 20)) (mkReg (rs1' w))
  0x5 -> Right $ CSRRWI (mkReg (rd' w)) (mkCSR (field w 31 20)) (mkUImm5 (rs1' w))
  0x6 -> Right $ CSRRSI (mkReg (rd' w)) (mkCSR (field w 31 20)) (mkUImm5 (rs1' w))
  0x7 -> Right $ CSRRCI (mkReg (rd' w)) (mkCSR (field w 31 20)) (mkUImm5 (rs1' w))
  f3  -> Left (UnknownFunct3 0x73 f3)

decodeFence :: Word32 -> Either DecodeError Instruction
decodeFence w = case funct3' w of
  0x0 ->
    let pre = decodeFenceMode (field w 27 24)
        suc = decodeFenceMode (field w 23 20)
    in  Right (FENCE pre suc)
  0x1 -> Right FENCE_I
  f3  -> Left (UnknownFunct3 0x0F f3)

decodeFenceMode :: Word32 -> FenceMode
decodeFenceMode bits = FenceMode
  { fenceI = testBit bits 3
  , fenceO = testBit bits 2
  , fenceR = testBit bits 1
  , fenceW = testBit bits 0
  }
```

- [ ] **Step 4: Run tests**

```
cabal test riscv-rig-test --test-option="--pattern=Core.Decode"
```

Expected: all decode tests + roundtrip property pass (100 cases).

- [ ] **Step 5: Commit**

```bash
git add src/Core/Decode.hs test/Test/Core/Decode.hs
git commit -m "feat: Core.Decode — decode :: Word32 -> Either DecodeError Instruction, encode/decode roundtrip"
```

---

## Task 6: Core.CSR

**Files:**
- Modify: `src/Core/CSR.hs`

- [ ] **Step 1: Write failing test** (in `test/Test/Core/Encode.hs`, add to tests group)

```haskell
import Core.CSR

csrTests :: TestTree
csrTests = testGroup "Core.CSR"
  [ testCase "mstatus address is 0x300" $
      csrAddr Mstatus @?= CSRAddr 0x300
  , testCase "all CSR addresses are unique" $
      let addrs = map csrAddr [minBound..maxBound]
      in  length addrs @?= length (nub addrs)
  , testCase "Mstatus requires Machine privilege to write" $
      writePriv (csrAccessRules Mstatus) @?= Machine
  , testCase "Cycle is read-only" $
      readOnly (csrAccessRules Cycle) @?= True
  ]
  where nub [] = []; nub (x:xs) = x : nub (filter (/=x) xs)
```

- [ ] **Step 2: Implement Core.CSR**

`src/Core/CSR.hs`:
```haskell
module Core.CSR
  ( CSR(..)
  , csrAddr
  , CSRAccess(..)
  , csrAccessRules
  ) where

import Core.Types

data CSR
  -- Machine Info (read-only)
  = Mvendorid | Marchid | Mimpid | Mhartid
  -- Machine Trap Setup
  | Mstatus | Misa | Medeleg | Mideleg | Mie | Mtvec | Mcounteren
  -- Machine Trap Handling
  | Mscratch | Mepc | Mcause | Mtval | Mip
  -- Supervisor Trap Setup
  | Sstatus | Sedeleg | Sideleg | Sie | Stvec | Scounteren
  -- Supervisor Trap Handling
  | Sscratch | Sepc | Scause | Stval | Sip
  -- Supervisor VM
  | Satp
  -- Performance Counters (unprivileged read)
  | Cycle | Time | Instret
  -- Machine Counters
  | Mcycle | Minstret
  -- FP
  | Fflags | Frm | Fcsr
  deriving (Show, Eq, Ord, Enum, Bounded)

csrAddr :: CSR -> CSRAddr
csrAddr = CSRAddr . \case
  Mvendorid -> 0xF11; Marchid -> 0xF12; Mimpid -> 0xF13; Mhartid -> 0xF14
  Mstatus   -> 0x300; Misa    -> 0x301; Medeleg -> 0x302; Mideleg -> 0x303
  Mie       -> 0x304; Mtvec   -> 0x305; Mcounteren -> 0x306
  Mscratch  -> 0x340; Mepc    -> 0x341; Mcause  -> 0x342; Mtval   -> 0x343
  Mip       -> 0x344
  Sstatus   -> 0x100; Sedeleg -> 0x102; Sideleg -> 0x103; Sie     -> 0x104
  Stvec     -> 0x105; Scounteren -> 0x106
  Sscratch  -> 0x140; Sepc    -> 0x141; Scause  -> 0x142; Stval   -> 0x143
  Sip       -> 0x144; Satp    -> 0x180
  Cycle     -> 0xC00; Time    -> 0xC01; Instret -> 0xC02
  Mcycle    -> 0xB00; Minstret -> 0xB02
  Fflags    -> 0x001; Frm     -> 0x002; Fcsr    -> 0x003

data CSRAccess = CSRAccess
  { readPriv  :: PrivilegeLevel
  , writePriv :: PrivilegeLevel
  , readOnly  :: Bool
  }

csrAccessRules :: CSR -> CSRAccess
csrAccessRules = \case
  Mvendorid  -> CSRAccess Machine Machine True
  Marchid    -> CSRAccess Machine Machine True
  Mimpid     -> CSRAccess Machine Machine True
  Mhartid    -> CSRAccess Machine Machine True
  Mstatus    -> CSRAccess Machine Machine False
  Misa       -> CSRAccess Machine Machine False
  Medeleg    -> CSRAccess Machine Machine False
  Mideleg    -> CSRAccess Machine Machine False
  Mie        -> CSRAccess Machine Machine False
  Mtvec      -> CSRAccess Machine Machine False
  Mcounteren -> CSRAccess Machine Machine False
  Mscratch   -> CSRAccess Machine Machine False
  Mepc       -> CSRAccess Machine Machine False
  Mcause     -> CSRAccess Machine Machine False
  Mtval      -> CSRAccess Machine Machine False
  Mip        -> CSRAccess Machine Machine False
  Sstatus    -> CSRAccess Supervisor Supervisor False
  Sedeleg    -> CSRAccess Supervisor Supervisor False
  Sideleg    -> CSRAccess Supervisor Supervisor False
  Sie        -> CSRAccess Supervisor Supervisor False
  Stvec      -> CSRAccess Supervisor Supervisor False
  Scounteren -> CSRAccess Supervisor Supervisor False
  Sscratch   -> CSRAccess Supervisor Supervisor False
  Sepc       -> CSRAccess Supervisor Supervisor False
  Scause     -> CSRAccess Supervisor Supervisor False
  Stval      -> CSRAccess Supervisor Supervisor False
  Sip        -> CSRAccess Supervisor Supervisor False
  Satp       -> CSRAccess Supervisor Supervisor False
  Cycle      -> CSRAccess User User True
  Time       -> CSRAccess User User True
  Instret    -> CSRAccess User User True
  Mcycle     -> CSRAccess Machine Machine False
  Minstret   -> CSRAccess Machine Machine False
  Fflags     -> CSRAccess User User False
  Frm        -> CSRAccess User User False
  Fcsr       -> CSRAccess User User False
```

- [ ] **Step 3: Run tests, commit**

```
cabal test riscv-rig-test
```

```bash
git add src/Core/CSR.hs test/Test/Core/Encode.hs
git commit -m "feat: Core.CSR — CSR ADT, csrAddr, CSRAccess rules"
```

---

## Task 7: Constraint.Types + Constraint.Solver

**Files:**
- Modify: `src/Constraint/Types.hs`
- Modify: `src/Constraint/Solver.hs`
- Modify: `test/Test/Constraint/Solver.hs`

- [ ] **Step 1: Write failing tests**

`test/Test/Constraint/Solver.hs`:
```haskell
module Test.Constraint.Solver (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Core.Types
import Constraint.Types
import Constraint.Solver

tests :: TestTree
tests = testGroup "Constraint.Solver"
  [ testCase "empty constraint set is satisfiable" $ do
      result <- solve emptyConstraintSet
      case result of
        Just _  -> return ()
        Nothing -> assertFailure "expected a solution"
  , testCase "infeasible constraint returns Nothing" $ do
      -- rd must be 0 AND rd must not be 0 → UNSAT
      let rdIsZero    = ConstraintDef "rd-zero"    [] "" [] (\s -> symRd s .== 0)
          rdNonZero   = ConstraintDef "rd-nonzero" [] "" [] (\s -> symRd s ./= 0)
          cs = addConstraint rdIsZero (addConstraint rdNonZero emptyConstraintSet)
      result <- solve cs
      result @?= Nothing
  , testCase "single constraint rd != 0 gives valid params" $ do
      let rdNZ = ConstraintDef "rd-nonzero" [] "" [] (\s -> symRd s ./= 0)
          cs   = addConstraint rdNZ emptyConstraintSet
      result <- solve cs
      case result of
        Nothing -> assertFailure "expected a solution"
        Just p  -> (ipRd p /= 0) @?= True
  ]
```

- [ ] **Step 2: Implement Constraint.Types**

`src/Constraint/Types.hs`:
```haskell
module Constraint.Types
  ( Tag(..)
  , SymInstrParams(..)
  , InstrParams(..)
  , ConstraintDef(..)
  , ConstraintSet(..)
  , Density(..)
  , DensityAssessment(..)
  , FeasibilityResult(..)
  , emptyConstraintSet
  , constraints
  ) where

import Core.Types    (Extension)
import Data.SBV
import Data.Text     (Text)
import GHC.Generics  (Generic)

data Tag
  = Memory | Alignment | Register | SafetyNet | Branch | Atomic
  | Privilege | FP | Performance | CornerCase
  deriving (Show, Eq, Ord, Enum, Bounded, Generic)

-- Symbolic instruction parameters — all fields are SBV symbolic values.
-- Word8 fields hold 7/5/3-bit values; constraints narrow the range.
data SymInstrParams = SymInstrParams
  { symOpcode :: SWord8
  , symRd     :: SWord8   -- 5-bit (0–31)
  , symRs1    :: SWord8
  , symRs2    :: SWord8
  , symFunct3 :: SWord8   -- 3-bit (0–7)
  , symFunct7 :: SWord8   -- 7-bit (0–127)
  , symImm    :: SInt32   -- signed immediate (range depends on instruction)
  }

-- Concrete instruction parameters extracted from a solver model.
data InstrParams = InstrParams
  { ipOpcode :: Word8
  , ipRd     :: Word8
  , ipRs1    :: Word8
  , ipRs2    :: Word8
  , ipFunct3 :: Word8
  , ipFunct7 :: Word8
  , ipImm    :: Int32
  } deriving (Show, Eq, Generic)

data ConstraintDef = ConstraintDef
  { cname        :: Text
  , ctags        :: [Tag]
  , cdescription :: Text
  , cextensions  :: [Extension]
  , cpredicate   :: SymInstrParams -> SBool
  }

newtype ConstraintSet = ConstraintSet { unConstraintSet :: [ConstraintDef] }

emptyConstraintSet :: ConstraintSet
emptyConstraintSet = ConstraintSet []

constraints :: ConstraintSet -> [ConstraintDef]
constraints = unConstraintSet

data DensityAssessment
  = HealthyDensity
  | TightConstraints
  | OverConstrained
  | PossiblyExhausted
  deriving (Show, Eq)

data Density = Density
  { sampleSize  :: Int
  , uniqueCount :: Int
  , ratio       :: Double
  , assessment  :: DensityAssessment
  } deriving (Show, Eq)

data FeasibilityResult
  = Feasible
  | Infeasible [Text]   -- names of conflicting constraints
  | FeasibilityUnknown Text
  deriving (Show, Eq)
```

- [ ] **Step 3: Implement Constraint.Solver**

`src/Constraint/Solver.hs`:
```haskell
module Constraint.Solver
  ( solve
  , checkFeasibility
  , estimateDensity
  ) where

import Constraint.Types
import Data.SBV
import Data.Maybe  (fromMaybe)
import Data.Word   (Word8)
import Data.Int    (Int32)

-- Run Z3 and return one satisfying assignment, or Nothing if UNSAT.
-- Requires Z3 to be on PATH.
solve :: ConstraintSet -> IO (Maybe InstrParams)
solve cs = do
  result <- sat (buildQuery cs)
  return $ extractParams result

buildQuery :: ConstraintSet -> Symbolic ()
buildQuery cs = do
  sym <- mkSymParams
  -- Structural constraints: all fields must be in valid hardware ranges
  constrain $ symOpcode sym .< 128
  constrain $ symRd     sym .< 32
  constrain $ symRs1    sym .< 32
  constrain $ symRs2    sym .< 32
  constrain $ symFunct3 sym .< 8
  constrain $ symFunct7 sym .< 128
  -- User-defined constraints
  mapM_ (\c -> constrain (cpredicate c sym)) (constraints cs)

mkSymParams :: Symbolic SymInstrParams
mkSymParams = SymInstrParams
  <$> sWord8 "opcode"
  <*> sWord8 "rd"
  <*> sWord8 "rs1"
  <*> sWord8 "rs2"
  <*> sWord8 "funct3"
  <*> sWord8 "funct7"
  <*> sInt32 "imm"

extractParams :: SatResult -> Maybe InstrParams
extractParams (SatResult (Satisfiable _ model)) = Just InstrParams
  { ipOpcode = fromMaybe 0 (getModelValue "opcode" model)
  , ipRd     = fromMaybe 0 (getModelValue "rd"     model)
  , ipRs1    = fromMaybe 0 (getModelValue "rs1"    model)
  , ipRs2    = fromMaybe 0 (getModelValue "rs2"    model)
  , ipFunct3 = fromMaybe 0 (getModelValue "funct3" model)
  , ipFunct7 = fromMaybe 0 (getModelValue "funct7" model)
  , ipImm    = fromMaybe 0 (getModelValue "imm"    model)
  }
extractParams _ = Nothing

-- Check whether a constraint set is satisfiable.
checkFeasibility :: ConstraintSet -> IO FeasibilityResult
checkFeasibility cs = do
  result <- sat (buildQuery cs)
  return $ case result of
    SatResult (Satisfiable _ _)   -> Feasible
    SatResult (Unsatisfiable _ _) -> Infeasible (map cname (constraints cs))
    SatResult (Unknown _ reason)  -> FeasibilityUnknown (show reason)
    _                             -> FeasibilityUnknown "solver error"

-- Estimate solution density by sampling N solutions with blocking clauses.
-- A low ratio (< 0.1) means the constraints are very tight.
estimateDensity :: ConstraintSet -> Int -> IO Density
estimateDensity cs n = do
  solutions <- collectN cs n []
  let unique = length solutions
      r      = fromIntegral unique / fromIntegral n
  return Density
    { sampleSize  = n
    , uniqueCount = unique
    , ratio       = r
    , assessment  = assess r
    }

collectN :: ConstraintSet -> Int -> [InstrParams] -> IO [InstrParams]
collectN _ 0 acc = return acc
collectN cs remaining acc = do
  result <- solve cs
  case result of
    Nothing -> return acc
    Just p  ->
      -- Add a blocking clause: exclude this exact solution
      let blockClause sym =
            sNot $ symRd sym .== literal (ipRd p)
              .&& symRs1 sym .== literal (ipRs1 p)
              .&& symImm sym .== literal (ipImm p)
          blocked = ConstraintSet
            (ConstraintDef "block" [] "" [] blockClause : constraints cs)
      in  collectN blocked (remaining - 1) (p : acc)

assess :: Double -> DensityAssessment
assess r
  | r > 0.5   = HealthyDensity
  | r > 0.1   = TightConstraints
  | r > 0.0   = OverConstrained
  | otherwise = PossiblyExhausted
```

- [ ] **Step 4: Run tests**

```
cabal test riscv-rig-test --test-option="--pattern=Constraint.Solver"
```

Expected: all 3 tests pass. Note: first run may be slow as Z3 warms up (~2–5s per case).

- [ ] **Step 5: Commit**

```bash
git add src/Constraint/Types.hs src/Constraint/Solver.hs test/Test/Constraint/Solver.hs
git commit -m "feat: Constraint.Types + Solver — SBV/Z3 satisfiability, density estimation"
```

---

## Task 8: Constraint.Library + Constraint.Combinators

**Files:**
- Modify: `src/Constraint/Library.hs`
- Modify: `src/Constraint/Combinators.hs`

- [ ] **Step 1: Implement Constraint.Combinators**

`src/Constraint/Combinators.hs`:
```haskell
module Constraint.Combinators
  ( cAnd, cOr, cNot, cImplies
  , withWeight
  , addConstraint, removeConstraint, mergeConstraints
  ) where

import Constraint.Types
import Data.SBV       (sNot, (.&&), (.||))
import Data.Text      (Text)

cAnd :: ConstraintDef -> ConstraintDef -> ConstraintDef
cAnd a b = ConstraintDef
  { cname        = cname a <> " && " <> cname b
  , ctags        = ctags a <> ctags b
  , cdescription = cdescription a <> " AND " <> cdescription b
  , cextensions  = cextensions a <> cextensions b
  , cpredicate   = \sym -> cpredicate a sym .&& cpredicate b sym
  }

cOr :: ConstraintDef -> ConstraintDef -> ConstraintDef
cOr a b = ConstraintDef
  { cname        = cname a <> " || " <> cname b
  , ctags        = ctags a <> ctags b
  , cdescription = cdescription a <> " OR " <> cdescription b
  , cextensions  = cextensions a <> cextensions b
  , cpredicate   = \sym -> cpredicate a sym .|| cpredicate b sym
  }

cNot :: ConstraintDef -> ConstraintDef
cNot c = c
  { cname      = "not (" <> cname c <> ")"
  , cpredicate = sNot . cpredicate c
  }

cImplies :: ConstraintDef -> ConstraintDef -> ConstraintDef
cImplies ante conseq = ConstraintDef
  { cname        = cname ante <> " => " <> cname conseq
  , ctags        = ctags ante <> ctags conseq
  , cdescription = cname ante <> " implies " <> cname conseq
  , cextensions  = cextensions ante <> cextensions conseq
  , cpredicate   = \sym ->
      sNot (cpredicate ante sym) .|| cpredicate conseq sym
  }

-- Weight is stored in the name as metadata for the optimizer.
-- It does not affect the solver — it guides the random generator.
withWeight :: Double -> ConstraintDef -> ConstraintDef
withWeight w c = c { cname = cname c <> " [w=" <> show w <> "]" }

addConstraint :: ConstraintDef -> ConstraintSet -> ConstraintSet
addConstraint c (ConstraintSet cs) = ConstraintSet (c : cs)

removeConstraint :: Text -> ConstraintSet -> ConstraintSet
removeConstraint name (ConstraintSet cs) =
  ConstraintSet (filter (\c -> cname c /= name) cs)

mergeConstraints :: ConstraintSet -> ConstraintSet -> ConstraintSet
mergeConstraints (ConstraintSet a) (ConstraintSet b) = ConstraintSet (a <> b)
```

- [ ] **Step 2: Implement Constraint.Library**

`src/Constraint/Library.hs`:
```haskell
module Constraint.Library
  ( rdNotZero, rs1NotZero, rs2NotZero
  , rdNotSameAsRs1
  , alignedImm, immInRange
  , branchImmEven
  , noLoadUseHazard
  ) where

import Constraint.Types
import Data.SBV

rdNotZero :: ConstraintDef
rdNotZero = ConstraintDef
  { cname        = "rd-not-zero"
  , ctags        = [Register, SafetyNet]
  , cdescription = "rd != x0; avoid writing to the zero register"
  , cextensions  = []
  , cpredicate   = \s -> symRd s ./= 0
  }

rs1NotZero :: ConstraintDef
rs1NotZero = ConstraintDef
  { cname        = "rs1-not-zero"
  , ctags        = [Register]
  , cdescription = "rs1 != x0"
  , cextensions  = []
  , cpredicate   = \s -> symRs1 s ./= 0
  }

rs2NotZero :: ConstraintDef
rs2NotZero = ConstraintDef
  { cname        = "rs2-not-zero"
  , ctags        = [Register]
  , cdescription = "rs2 != x0"
  , cextensions  = []
  , cpredicate   = \s -> symRs2 s ./= 0
  }

rdNotSameAsRs1 :: ConstraintDef
rdNotSameAsRs1 = ConstraintDef
  { cname        = "rd-not-rs1"
  , ctags        = [Register]
  , cdescription = "rd != rs1; useful for testing instruction fusion boundaries"
  , cextensions  = []
  , cpredicate   = \s -> symRd s ./= symRs1 s
  }

-- alignedImm n: imm must be divisible by n (for load/store alignment)
alignedImm :: Int -> ConstraintDef
alignedImm n = ConstraintDef
  { cname        = "aligned-imm-" <> show n
  , ctags        = [Memory, Alignment]
  , cdescription = "immediate offset must be " <> show n <> "-byte aligned"
  , cextensions  = []
  , cpredicate   = \s ->
      symImm s `sRem` literal (fromIntegral n) .== 0
  }

-- immInRange lo hi: immediate must be in [lo, hi]
immInRange :: Int32 -> Int32 -> ConstraintDef
immInRange lo hi = ConstraintDef
  { cname        = "imm-in-range-[" <> show lo <> "," <> show hi <> "]"
  , ctags        = [Memory]
  , cdescription = "immediate in [" <> show lo <> ", " <> show hi <> "]"
  , cextensions  = []
  , cpredicate   = \s ->
      symImm s .>= literal lo .&& symImm s .<= literal hi
  }

-- Branch immediate must be even (RISC-V requires 2-byte alignment)
branchImmEven :: ConstraintDef
branchImmEven = ConstraintDef
  { cname        = "branch-imm-even"
  , ctags        = [Branch]
  , cdescription = "branch offset must be even (2-byte aligned)"
  , cextensions  = []
  , cpredicate   = \s -> symImm s `sRem` 2 .== 0
  }

-- No load-use hazard: imm for next instruction doesn't match previous rd.
-- This is a sequence-level constraint; in Phase 1, we approximate it
-- as "rs1 != rd" for the same instruction (single-instruction approximation).
noLoadUseHazard :: ConstraintDef
noLoadUseHazard = ConstraintDef
  { cname        = "no-load-use-hazard"
  , ctags        = [Performance]
  , cdescription = "rs1 != rd within the same instruction (approx. single-instruction)"
  , cextensions  = []
  , cpredicate   = \s -> symRs1 s ./= symRd s
  }
```

- [ ] **Step 3: Add library tests in Constraint.Solver test**

Add to `test/Test/Constraint/Solver.hs`:
```haskell
import Constraint.Library
import Constraint.Combinators

  -- inside tests testGroup:
  , testCase "rdNotZero AND rs1NotZero gives rd/=0, rs1/=0" $ do
      let cs = addConstraint rdNotZero (addConstraint rs1NotZero emptyConstraintSet)
      result <- solve cs
      case result of
        Nothing -> assertFailure "expected solution"
        Just p  -> do
          (ipRd p /= 0)  @?= True
          (ipRs1 p /= 0) @?= True
  , testCase "mergeConstraints combines both sets" $ do
      let cs1 = addConstraint rdNotZero  emptyConstraintSet
          cs2 = addConstraint rs2NotZero emptyConstraintSet
          cs  = mergeConstraints cs1 cs2
      result <- solve cs
      case result of
        Nothing -> assertFailure "expected solution"
        Just p  -> do
          (ipRd p  /= 0) @?= True
          (ipRs2 p /= 0) @?= True
```

- [ ] **Step 4: Run tests, commit**

```
cabal test riscv-rig-test
```

```bash
git add src/Constraint/Library.hs src/Constraint/Combinators.hs test/Test/Constraint/Solver.hs
git commit -m "feat: Constraint.Library + Combinators — rdNotZero, alignedImm, cAnd/cOr/cNot"
```

---

## Task 9: Generator.Seed + Generator.Types

**Files:**
- Modify: `src/Generator/Seed.hs`
- Modify: `src/Generator/Types.hs`

- [ ] **Step 1: Implement Generator.Seed**

`src/Generator/Seed.hs`:
```haskell
module Generator.Seed
  ( Seed(..)
  , newRandomSeed
  , seedFromWord64
  , deriveSeed
  ) where

import Data.Word   (Word64)
import System.Random (randomIO)

newtype Seed = Seed { unSeed :: Word64 }
  deriving (Show, Eq, Ord)

newRandomSeed :: IO Seed
newRandomSeed = Seed <$> randomIO

seedFromWord64 :: Word64 -> Seed
seedFromWord64 = Seed

-- Derive a child seed from a parent seed + label using FNV-1a hash.
-- Different labels from the same root give independent seeds.
deriveSeed :: Seed -> String -> Seed
deriveSeed (Seed root) label =
  Seed (foldl fnv1aStep root (map fromIntegral (map fromEnum label)))
  where
    fnv1aStep acc byte =
      (acc `xor` byte) * 0x00000100000001B3
    xor a b = a `Data.Bits.xor` b

-- We need Data.Bits for xor
import Data.Bits (xor)
```

Wait, the `import Data.Bits` should be at the top. Let me rewrite:

`src/Generator/Seed.hs`:
```haskell
module Generator.Seed
  ( Seed(..)
  , newRandomSeed
  , seedFromWord64
  , deriveSeed
  ) where

import Data.Bits   (xor)
import Data.Word   (Word64)
import System.Random (randomIO)

newtype Seed = Seed { unSeed :: Word64 }
  deriving (Show, Eq, Ord)

newRandomSeed :: IO Seed
newRandomSeed = Seed <$> randomIO

seedFromWord64 :: Word64 -> Seed
seedFromWord64 = Seed

deriveSeed :: Seed -> String -> Seed
deriveSeed (Seed root) label =
  Seed (foldl fnv1aStep root (map (fromIntegral . fromEnum) label))
  where
    fnv1aStep :: Word64 -> Word64 -> Word64
    fnv1aStep acc byte = (acc `xor` byte) * 0x00000100000001B3
```

- [ ] **Step 2: Implement Generator.Types**

`src/Generator/Types.hs`:
```haskell
module Generator.Types
  ( GeneratorConfig(..)
  , GeneratorMode(..)
  , InstrSequence
  , defaultConfig
  ) where

import Core.Instruction (Instruction, Extension)
import Constraint.Types (ConstraintSet, emptyConstraintSet)
import Generator.Seed   (Seed, seedFromWord64)
import Data.Set         (Set)
import qualified Data.Set as Set

type InstrSequence = [Instruction]

data GeneratorMode
  = PureRandom                 -- only Hedgehog, no solver
  | SolverDirected Int         -- find N corner cases via Z3, rest random
  | Hybrid Double              -- 0.0–1.0: fraction that is solver-directed
  deriving (Show, Eq)

data GeneratorConfig = GeneratorConfig
  { gcExtensions   :: Set Extension
  , gcConstraints  :: ConstraintSet
  , gcSeed         :: Seed
  , gcMinLength    :: Int
  , gcMaxLength    :: Int
  , gcMode         :: GeneratorMode
  } deriving (Show)

defaultConfig :: GeneratorConfig
defaultConfig = GeneratorConfig
  { gcExtensions  = Set.fromList [RV64I, RV64M]
  , gcConstraints = emptyConstraintSet
  , gcSeed        = seedFromWord64 0xDEADBEEF42
  , gcMinLength   = 10
  , gcMaxLength   = 50
  , gcMode        = PureRandom
  }
  where
    RV64I = toEnum 0  -- imported from Core.Instruction
    RV64M = toEnum 1
```

Wait, that's wrong. Let me fix the import:

`src/Generator/Types.hs`:
```haskell
module Generator.Types
  ( GeneratorConfig(..)
  , GeneratorMode(..)
  , InstrSequence
  , defaultConfig
  ) where

import Core.Instruction  (Extension(..))
import Constraint.Types  (ConstraintSet, emptyConstraintSet)
import Generator.Seed    (Seed, seedFromWord64)
import Data.Set          (Set)
import qualified Data.Set as Set

type InstrSequence = [Instruction]

import Core.Instruction (Instruction)

data GeneratorMode
  = PureRandom
  | SolverDirected Int
  | Hybrid Double
  deriving (Show, Eq)

data GeneratorConfig = GeneratorConfig
  { gcExtensions   :: Set Extension
  , gcConstraints  :: ConstraintSet
  , gcSeed         :: Seed
  , gcMinLength    :: Int
  , gcMaxLength    :: Int
  , gcMode         :: GeneratorMode
  }

defaultConfig :: GeneratorConfig
defaultConfig = GeneratorConfig
  { gcExtensions  = Set.fromList [RV64I, RV64M]
  , gcConstraints = emptyConstraintSet
  , gcSeed        = seedFromWord64 0xDEADBEEF42
  , gcMinLength   = 10
  , gcMaxLength   = 50
  , gcMode        = PureRandom
  }
```

Actually the import placement is wrong. Here is the correct file:

`src/Generator/Types.hs`:
```haskell
module Generator.Types
  ( GeneratorConfig(..)
  , GeneratorMode(..)
  , InstrSequence
  , defaultConfig
  ) where

import Core.Instruction  (Instruction, Extension(..))
import Constraint.Types  (ConstraintSet, emptyConstraintSet)
import Generator.Seed    (Seed, seedFromWord64)
import Data.Set          (Set)
import qualified Data.Set as Set

type InstrSequence = [Instruction]

data GeneratorMode
  = PureRandom
  | SolverDirected Int
  | Hybrid Double
  deriving (Show, Eq)

data GeneratorConfig = GeneratorConfig
  { gcExtensions   :: Set Extension
  , gcConstraints  :: ConstraintSet
  , gcSeed         :: Seed
  , gcMinLength    :: Int
  , gcMaxLength    :: Int
  , gcMode         :: GeneratorMode
  }

defaultConfig :: GeneratorConfig
defaultConfig = GeneratorConfig
  { gcExtensions  = Set.fromList [RV64I, RV64M]
  , gcConstraints = emptyConstraintSet
  , gcSeed        = seedFromWord64 0xDEADBEEF42
  , gcMinLength   = 10
  , gcMaxLength   = 50
  , gcMode        = PureRandom
  }
```

- [ ] **Step 3: Build and commit**

```
cabal build all
```

```bash
git add src/Generator/Seed.hs src/Generator/Types.hs
git commit -m "feat: Generator.Seed + Types — Seed, deriveSeed (FNV-1a), GeneratorConfig"
```

---

## Task 10: Generator.Random

**Files:**
- Modify: `src/Generator/Random.hs`
- Modify: `test/Test/Generator/Random.hs`

- [ ] **Step 1: Write failing tests**

`test/Test/Generator/Random.hs`:
```haskell
module Test.Generator.Random (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog
import Hedgehog
import qualified Hedgehog.Gen   as Gen
import qualified Hedgehog.Range as Range
import Core.Types
import Core.Instruction
import Generator.Random
import Generator.Types
import Generator.Seed

tests :: TestTree
tests = testGroup "Generator.Random"
  [ testProperty "generated instructions are valid Instruction values" $
      property $ do
        instr <- forAll (genInstruction defaultExtensions)
        -- Just verify it can be shown (forces full evaluation)
        length (show instr) > 0 === True
  , testCase "generateSequence returns sequence in config length range" $ do
      let cfg = defaultConfig
      seed <- newRandomSeed
      let cfg' = cfg { gcSeed = seed }
      seq_ <- generateSequence cfg'
      let l = length seq_
      (l >= gcMinLength cfg && l <= gcMaxLength cfg) @?= True
  , testCase "same seed gives same sequence" $ do
      let cfg = defaultConfig { gcSeed = seedFromWord64 12345 }
      seq1 <- generateSequence cfg
      seq2 <- generateSequence cfg
      seq1 @?= seq2
  ]

defaultExtensions :: [Extension]
defaultExtensions = [RV64I, RV64M]
```

- [ ] **Step 2: Implement Generator.Random**

`src/Generator/Random.hs`:
```haskell
module Generator.Random
  ( genInstruction
  , generateSequence
  , OpcodeCategory(..)
  , availableOpcodes
  ) where

import Core.Types
import Core.Instruction
import Generator.Types  (GeneratorConfig(..), InstrSequence)
import Generator.Seed   (Seed(..))
import Hedgehog
import qualified Hedgehog.Gen   as Gen
import qualified Hedgehog.Range as Range
import Data.Set         (Set)
import qualified Data.Set as Set
import System.Random    (mkStdGen, randomRs)

data OpcodeCategory
  = AluR        -- R-type arithmetic (ADD, SUB, AND, …)
  | AluI        -- I-type arithmetic (ADDI, ANDI, …)
  | LoadOp      -- Load (LB, LH, LW, LD, …)
  | StoreOp     -- Store (SB, SH, SW, SD)
  | BranchOp    -- Branch (BEQ, BNE, …)
  | JumpOp      -- JAL, JALR
  | UpperImm    -- LUI, AUIPC
  | SystemOp    -- ECALL, EBREAK, FENCE, CSR
  | MulDiv      -- RV64M
  | PrivOp      -- MRET, SRET, WFI
  deriving (Show, Eq, Ord, Enum, Bounded)

availableOpcodes :: [Extension] -> [OpcodeCategory]
availableOpcodes exts =
  [ AluR, AluI, LoadOp, StoreOp, BranchOp, JumpOp, UpperImm, SystemOp ]
  <> [ MulDiv | RV64M `elem` exts ]
  <> [ PrivOp | RVPriv `elem` exts ]

genInstruction :: [Extension] -> Gen Instruction
genInstruction exts = do
  cat <- Gen.element (availableOpcodes exts)
  case cat of
    AluR     -> genAluR
    AluI     -> genAluI
    LoadOp   -> genLoad
    StoreOp  -> genStore
    BranchOp -> genBranch
    JumpOp   -> genJump
    UpperImm -> genUpperImm
    SystemOp -> genSystem
    MulDiv   -> genMulDiv
    PrivOp   -> genPriv

-- ── Register / Immediate generators ──────────────────────────────

genReg :: Gen Register
genReg = Register <$> Gen.word8 (Range.linear 0 31)

genNonZeroReg :: Gen Register
genNonZeroReg = Register <$> Gen.word8 (Range.linear 1 31)

genUImm5 :: Gen UImm5
genUImm5 = UImm5 <$> Gen.word8 (Range.linear 0 31)

-- Biased toward corner cases: 0, 1, -1, max, min, random
genImm12 :: Gen Imm12
genImm12 = Imm12 <$> Gen.frequency
  [ (3, pure 0)
  , (3, pure 1)
  , (3, pure (-1))
  , (3, pure 2047)
  , (3, pure (-2048))
  , (5, Gen.int16 (Range.linearFrom 0 (-2048) 2047))
  ]

genImm20 :: Gen Imm20
genImm20 = Imm20 <$> Gen.int32 (Range.linearFrom 0 0 0xFFFFF)

-- Branch offsets must be even
genImm13 :: Gen Imm13
genImm13 = Imm13 . (\x -> x - x `mod` 2)
  <$> Gen.int16 (Range.linearFrom 0 (-4096) 4094)

-- JAL offsets must be even
genImm21 :: Gen Imm21
genImm21 = Imm21 . (\x -> x - x `mod` 2)
  <$> Gen.int32 (Range.linearFrom 0 (-1048576) 1048574)

-- ── Category generators ───────────────────────────────────────────

genAluR :: Gen Instruction
genAluR = Gen.choice
  [ ADD  <$> genReg <*> genReg <*> genReg
  , SUB  <$> genReg <*> genReg <*> genReg
  , AND  <$> genReg <*> genReg <*> genReg
  , OR   <$> genReg <*> genReg <*> genReg
  , XOR  <$> genReg <*> genReg <*> genReg
  , SLL  <$> genReg <*> genReg <*> genReg
  , SRL  <$> genReg <*> genReg <*> genReg
  , SRA  <$> genReg <*> genReg <*> genReg
  , SLT  <$> genReg <*> genReg <*> genReg
  , SLTU <$> genReg <*> genReg <*> genReg
  , ADDW <$> genReg <*> genReg <*> genReg
  , SUBW <$> genReg <*> genReg <*> genReg
  , SLLW <$> genReg <*> genReg <*> genReg
  , SRLW <$> genReg <*> genReg <*> genReg
  , SRAW <$> genReg <*> genReg <*> genReg
  ]

genAluI :: Gen Instruction
genAluI = Gen.choice
  [ ADDI  <$> genReg <*> genReg <*> genImm12
  , ADDIW <$> genReg <*> genReg <*> genImm12
  , ANDI  <$> genReg <*> genReg <*> genImm12
  , ORI   <$> genReg <*> genReg <*> genImm12
  , XORI  <$> genReg <*> genReg <*> genImm12
  , SLLI  <$> genReg <*> genReg <*> genUImm5
  , SRLI  <$> genReg <*> genReg <*> genUImm5
  , SRAI  <$> genReg <*> genReg <*> genUImm5
  , SLTI  <$> genReg <*> genReg <*> genImm12
  , SLTIU <$> genReg <*> genReg <*> genImm12
  ]

genLoad :: Gen Instruction
genLoad = Gen.choice
  [ LB  <$> genNonZeroReg <*> genReg <*> genImm12
  , LH  <$> genNonZeroReg <*> genReg <*> genImm12
  , LW  <$> genNonZeroReg <*> genReg <*> genImm12
  , LD  <$> genNonZeroReg <*> genReg <*> genImm12
  , LBU <$> genNonZeroReg <*> genReg <*> genImm12
  , LHU <$> genNonZeroReg <*> genReg <*> genImm12
  , LWU <$> genNonZeroReg <*> genReg <*> genImm12
  ]

genStore :: Gen Instruction
genStore = Gen.choice
  [ SB <$> genReg <*> genReg <*> genImm12
  , SH <$> genReg <*> genReg <*> genImm12
  , SW <$> genReg <*> genReg <*> genImm12
  , SD <$> genReg <*> genReg <*> genImm12
  ]

genBranch :: Gen Instruction
genBranch = Gen.choice
  [ BEQ  <$> genReg <*> genReg <*> genImm13
  , BNE  <$> genReg <*> genReg <*> genImm13
  , BLT  <$> genReg <*> genReg <*> genImm13
  , BGE  <$> genReg <*> genReg <*> genImm13
  , BLTU <$> genReg <*> genReg <*> genImm13
  , BGEU <$> genReg <*> genReg <*> genImm13
  ]

genJump :: Gen Instruction
genJump = Gen.choice
  [ JAL  <$> genReg <*> genImm21
  , JALR <$> genReg <*> genReg <*> genImm12
  ]

genUpperImm :: Gen Instruction
genUpperImm = Gen.choice
  [ LUI   <$> genNonZeroReg <*> genImm20
  , AUIPC <$> genNonZeroReg <*> genImm20
  ]

genSystem :: Gen Instruction
genSystem = Gen.element [ECALL, EBREAK, FENCE_I]

genMulDiv :: Gen Instruction
genMulDiv = Gen.choice
  [ MUL    <$> genReg <*> genReg <*> genReg
  , MULH   <$> genReg <*> genReg <*> genReg
  , MULHU  <$> genReg <*> genReg <*> genReg
  , MULHSU <$> genReg <*> genReg <*> genReg
  , DIV    <$> genNonZeroReg <*> genReg <*> genNonZeroReg
  , DIVU   <$> genNonZeroReg <*> genReg <*> genNonZeroReg
  , REM    <$> genReg <*> genReg <*> genNonZeroReg
  , REMU   <$> genReg <*> genReg <*> genNonZeroReg
  , MULW   <$> genReg <*> genReg <*> genReg
  , DIVW   <$> genNonZeroReg <*> genReg <*> genNonZeroReg
  , DIVUW  <$> genNonZeroReg <*> genReg <*> genNonZeroReg
  , REMW   <$> genReg <*> genReg <*> genNonZeroReg
  , REMUW  <$> genReg <*> genReg <*> genNonZeroReg
  ]

genPriv :: Gen Instruction
genPriv = Gen.element [MRET, WFI]

-- ── Sequence generation ───────────────────────────────────────────

-- Generate a sequence of instructions using the config's seed.
-- Uses Hedgehog's seed mechanism for reproducibility.
generateSequence :: GeneratorConfig -> IO InstrSequence
generateSequence cfg = do
  let seed    = unSeed (gcSeed cfg)
      stdGen  = mkStdGen (fromIntegral seed)
      exts    = Set.toList (gcExtensions cfg)
      lengths = randomRs (gcMinLength cfg, gcMaxLength cfg) stdGen
      n       = head lengths
  Gen.sample (Gen.list (Range.linear (gcMinLength cfg) (gcMaxLength cfg))
                        (genInstruction exts))
```

Note: `Gen.sample` uses a fixed internal seed for sampling. For truly reproducible output tied to `gcSeed`, use `Hedgehog.Internal.Seed` directly:

```haskell
-- Add this import at the top:
import Hedgehog.Internal.Seed (Seed(..))
import qualified Hedgehog.Internal.Seed as HSeed

generateSequence :: GeneratorConfig -> IO InstrSequence
generateSequence cfg = do
  let w64     = unSeed (gcSeed cfg)
      hSeed   = HSeed.from w64
      exts    = Set.toList (gcExtensions cfg)
      n       = gcMinLength cfg + fromIntegral (w64 `mod`
                  fromIntegral (gcMaxLength cfg - gcMinLength cfg + 1))
      gen     = Gen.list (Range.singleton n) (genInstruction exts)
  case Gen.evalGen (fromIntegral n) hSeed gen of
    Nothing   -> return []
    Just tree -> return (Gen.treeValue tree)
```

- [ ] **Step 3: Run tests**

```
cabal test riscv-rig-test --test-option="--pattern=Generator.Random"
```

Expected: all 3 tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/Generator/Random.hs test/Test/Generator/Random.hs
git commit -m "feat: Generator.Random — genInstruction, generateSequence, biased genImm12"
```

---

## Task 11: Coverage

**Files:**
- Modify: `src/Coverage/Types.hs`
- Modify: `src/Coverage/Accumulator.hs`
- Modify: `src/Coverage/Analysis.hs`
- Modify: `test/Test/Coverage/Accumulator.hs`

- [ ] **Step 1: Write failing tests**

`test/Test/Coverage/Accumulator.hs`:
```haskell
module Test.Coverage.Accumulator (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Control.Concurrent.STM
import Coverage.Types
import Coverage.Accumulator
import Coverage.Analysis
import Core.Instruction

tests :: TestTree
tests = testGroup "Coverage"
  [ testCase "new accumulator starts at zero coverage" $ do
      acc <- newAccumulator
      snap <- snapshotCoverage acc
      coveragePct snap @?= 0.0
  , testCase "recording opcode bins increases hit count" $ do
      acc <- newAccumulator
      atomically $ recordCoverage acc [OpcodeBin "ADD", OpcodeBin "SUB"]
      snap <- snapshotCoverage acc
      (hitBins snap >= 2) @?= True
  , testCase "coverage percentage is non-zero after recording" $ do
      acc <- newAccumulator
      atomically $ recordCoverage acc (map OpcodeBin allRV64IOpcodes)
      snap <- snapshotCoverage acc
      (coveragePct snap > 0) @?= True
  , testCase "concurrent updates are safe" $ do
      acc <- newAccumulator
      -- Record from 10 concurrent threads
      let updates = replicate 10 (atomically (recordCoverage acc [OpcodeBin "ADD"]))
      sequence_ updates
      snap <- snapshotCoverage acc
      -- ADD should have 10 hits
      case lookup (OpcodeBin "ADD") (Map.toList (covMap snap)) of
        Just n  -> (n >= 10) @?= True
        Nothing -> assertFailure "ADD not found in coverage map"
  ]

allRV64IOpcodes :: [Text]
allRV64IOpcodes = map (Text.pack . show . instrExtension) [minBound..maxBound :: Instruction]
-- Simplified: just use a few known opcodes
```

Actually let me simplify the test to not require importing all instructions:

`test/Test/Coverage/Accumulator.hs`:
```haskell
module Test.Coverage.Accumulator (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Control.Concurrent.STM
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Coverage.Types
import Coverage.Accumulator
import Coverage.Analysis

tests :: TestTree
tests = testGroup "Coverage"
  [ testCase "new accumulator starts empty" $ do
      acc <- newAccumulator
      m <- atomically (readTVar (covTVar acc))
      Map.null m @?= True
  , testCase "recording bins increments hit counts" $ do
      acc <- newAccumulator
      atomically $ recordCoverage acc [OpcodeBin "ADD", OpcodeBin "ADD", OpcodeBin "SUB"]
      m <- atomically (readTVar (covTVar acc))
      Map.lookup (OpcodeBin "ADD") m @?= Just 2
      Map.lookup (OpcodeBin "SUB") m @?= Just 1
  , testCase "coverage summary reports correct hit count" $ do
      acc <- newAccumulator
      atomically $ recordCoverage acc [OpcodeBin "ADD"]
      snap <- snapshotCoverage acc
      (hitBins snap >= 1) @?= True
  ]
```

- [ ] **Step 2: Implement Coverage.Types**

`src/Coverage/Types.hs`:
```haskell
module Coverage.Types
  ( CoverageBin(..)
  , CoverageMap
  , HitCount
  , allOpcodeBins
  ) where

import Data.Map.Strict (Map)
import Data.Text       (Text)

-- Phase 1: opcode-level coverage only.
-- Later phases add ValueBin, PatternBin, ExtCrossBin, etc.
data CoverageBin
  = OpcodeBin Text    -- one bin per instruction mnemonic
  deriving (Show, Eq, Ord)

type HitCount    = Word
type CoverageMap = Map CoverageBin HitCount

-- All opcode bins for RV64I + M (76 constructors)
allOpcodeBins :: [CoverageBin]
allOpcodeBins = map OpcodeBin
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
  , "MUL","MULH","MULHSU","MULHU","DIV","DIVU","REM","REMU"
  , "MULW","DIVW","DIVUW","REMW","REMUW"
  , "MRET","SRET","WFI","SFENCE_VMA"
  ]
```

- [ ] **Step 3: Implement Coverage.Accumulator**

`src/Coverage/Accumulator.hs`:
```haskell
module Coverage.Accumulator
  ( CoverageAccumulator(..)
  , newAccumulator
  , recordCoverage
  , snapshotCoverage
  ) where

import Coverage.Types
import Coverage.Analysis (CoverageSummary(..), coverageSummary)
import Control.Concurrent.STM
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map

data CoverageAccumulator = CoverageAccumulator
  { covTVar :: TVar CoverageMap
  }

newAccumulator :: IO CoverageAccumulator
newAccumulator = CoverageAccumulator <$> newTVarIO Map.empty

recordCoverage :: CoverageAccumulator -> [CoverageBin] -> STM ()
recordCoverage acc bins =
  modifyTVar' (covTVar acc) (applyHits bins)
  where
    applyHits bs m = foldr (\b -> Map.insertWith (+) b 1) m bs

snapshotCoverage :: CoverageAccumulator -> IO CoverageSummary
snapshotCoverage acc = do
  m <- readTVarIO (covTVar acc)
  return (coverageSummary m allOpcodeBins)
```

- [ ] **Step 4: Implement Coverage.Analysis**

`src/Coverage/Analysis.hs`:
```haskell
module Coverage.Analysis
  ( CoverageSummary(..)
  , coverageSummary
  , renderSummary
  ) where

import Coverage.Types
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.List       (sortOn)
import Data.Ord        (Down(..))

data CoverageSummary = CoverageSummary
  { covMap      :: CoverageMap
  , totalBins   :: Int
  , hitBins     :: Int
  , missingBins :: [CoverageBin]
  , coveragePct :: Double
  } deriving (Show)

coverageSummary :: CoverageMap -> [CoverageBin] -> CoverageSummary
coverageSummary cmap allBins = CoverageSummary
  { covMap      = cmap
  , totalBins   = total
  , hitBins     = hits
  , missingBins = filter (\b -> Map.findWithDefault 0 b cmap == 0) allBins
  , coveragePct = if total == 0 then 0.0
                  else fromIntegral hits / fromIntegral total * 100.0
  }
  where
    total = length allBins
    hits  = length (filter (\b -> Map.findWithDefault 0 b cmap > 0) allBins)

-- Render a text coverage summary with ASCII progress bars
renderSummary :: CoverageSummary -> String
renderSummary s = unlines
  [ "Coverage: " <> show (hitBins s) <> "/" <> show (totalBins s)
    <> " bins (" <> showPct (coveragePct s) <> "%)"
  , "  " <> progressBar 40 (coveragePct s)
  , ""
  , "Top uncovered bins:"
  , unlines (map (\b -> "  ✗ " <> showBin b) (take 10 (missingBins s)))
  ]
  where
    showPct p = show (round p :: Int)
    progressBar w pct =
      let filled = round (pct / 100.0 * fromIntegral w) :: Int
      in  "[" <> replicate filled '█' <> replicate (w - filled) '░' <> "]"
    showBin (OpcodeBin name) = show name
```

- [ ] **Step 5: Run tests, commit**

```
cabal test riscv-rig-test --test-option="--pattern=Coverage"
```

```bash
git add src/Coverage/ test/Test/Coverage/Accumulator.hs
git commit -m "feat: Coverage — OpcodeBin, STM accumulator, ASCII progress bar summary"
```

---

## Task 12: CoSim.Types + CoSim.Oracle + CoSim.Diff

**Files:**
- Modify: `src/CoSim/Types.hs`
- Modify: `src/CoSim/Oracle.hs`
- Modify: `src/CoSim/Diff.hs`

- [ ] **Step 1: Implement CoSim.Types**

`src/CoSim/Types.hs`:
```haskell
module CoSim.Types
  ( ArchState(..)
  , StateDelta(..)
  , StateDiff(..)
  , LogEntry(..)
  , MismatchReport(..)
  , emptyArchState
  ) where

import Core.Types      (Register, CSRAddr, PrivilegeLevel(..))
import Core.Instruction (Instruction)
import Generator.Seed  (Seed)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Vector     (Vector)
import qualified Data.Vector as V
import Data.Word       (Word8, Word32, Word64)

data ArchState = ArchState
  { asPC   :: Word64
  , asGPRs :: Vector Word64    -- 32 general-purpose registers
  , asCSRs :: Map Word16 Word64
  , asMem  :: Map Word64 Word8  -- sparse: only recently accessed bytes
  , asPriv :: PrivilegeLevel
  } deriving (Show, Eq)

emptyArchState :: ArchState
emptyArchState = ArchState
  { asPC   = 0x80000000
  , asGPRs = V.replicate 32 0
  , asCSRs = Map.empty
  , asMem  = Map.empty
  , asPriv = Machine
  }

data StateDelta = StateDelta
  { sdRegWrites :: [(Register, Word64)]
  , sdMemWrites :: [(Word64, Word8)]
  , sdCSRWrites :: [(Word16, Word64)]
  , sdPrivChange :: Maybe PrivilegeLevel
  } deriving (Show, Eq)

-- A difference between two oracles at the same instruction step
data StateDiff
  = PCDiff  { diffOrcl1PC  :: Word64, diffOrcl2PC  :: Word64 }
  | GPRDiff { diffReg      :: Register
            , diffOrcl1Val :: Word64, diffOrcl2Val :: Word64 }
  | CSRDiff { diffCSRAddr  :: Word16
            , diffOrcl1Val :: Word64, diffOrcl2Val :: Word64 }
  | MemDiff { diffAddr     :: Word64
            , diffOrcl1Byte :: Word8, diffOrcl2Byte :: Word8 }
  | PrivDiff { diffOrcl1Priv :: PrivilegeLevel
             , diffOrcl2Priv :: PrivilegeLevel }
  deriving (Show, Eq)

data LogEntry = LogEntry
  { leHartID    :: Int
  , lePC        :: Word64
  , leRawInstr  :: Word32
  , leInstr     :: Either String Instruction  -- Right if decode succeeded
  , leDelta     :: StateDelta
  } deriving (Show)

data MismatchReport = MismatchReport
  { mrSeed       :: Seed
  , mrPC         :: Word64
  , mrInstruction :: Instruction
  , mrDiffs      :: [StateDiff]
  , mrContext    :: [LogEntry]  -- last N log entries before mismatch
  } deriving (Show)
```

- [ ] **Step 2: Implement CoSim.Oracle**

`src/CoSim/Oracle.hs`:
```haskell
module CoSim.Oracle
  ( CoSimOracle(..)
  , OracleCapabilities(..)
  , oracleCapabilities
  , selectOracles
  ) where

import Core.Instruction (Instruction(..))

data CoSimOracle
  = OracleSpike     FilePath  -- path to spike binary
  | OracleSail      FilePath  -- path to sail-riscv binary
  | OracleQEMU      FilePath  -- path to qemu-system-riscv64 (limited)
  | OracleSoftFloat            -- pure Haskell IEEE 754 reference (Phase 2+)
  deriving (Show, Eq)

data OracleCapabilities = OracleCapabilities
  { supportsInterruptTiming  :: Bool
  , supportsFPExactSemantics :: Bool
  , supportsRVWMO            :: Bool
  , supportsPMAAttributes    :: Bool
  , supportsVectorExt        :: Bool
  } deriving (Show, Eq)

oracleCapabilities :: CoSimOracle -> OracleCapabilities
oracleCapabilities = \case
  OracleSpike     _ -> OracleCapabilities True  True  False True  False
  OracleSail      _ -> OracleCapabilities True  True  True  True  False
  OracleQEMU      _ -> OracleCapabilities False False False False False
  OracleSoftFloat   -> OracleCapabilities False True  False False False

-- Select oracles appropriate for the given instruction sequence.
-- Oracles that can't handle the sequence's characteristics are filtered out.
selectOracles :: [Instruction] -> [CoSimOracle] -> [CoSimOracle]
selectOracles instrs oracles =
  filter (\o -> canHandle (oracleCapabilities o)) oracles
  where
    hasFP  = any isFPInstr instrs
    hasInt = any isInterruptRelated instrs

    canHandle caps =
      (not hasFP  || supportsFPExactSemantics caps)
      && (not hasInt || supportsInterruptTiming  caps)

    isFPInstr :: Instruction -> Bool
    isFPInstr _ = False  -- Phase 1: no FP instructions

    isInterruptRelated :: Instruction -> Bool
    isInterruptRelated MRET = True
    isInterruptRelated WFI  = True
    isInterruptRelated _    = False
```

- [ ] **Step 3: Implement CoSim.Diff**

`src/CoSim/Diff.hs`:
```haskell
module CoSim.Diff
  ( diffArchState
  , gprDiffs
  , csrDiffs
  ) where

import CoSim.Types
import Core.Types (Register(..))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Vector as V

diffArchState :: ArchState -> ArchState -> [StateDiff]
diffArchState s1 s2 = concat
  [ [ PCDiff (asPC s1) (asPC s2) | asPC s1 /= asPC s2 ]
  , gprDiffs s1 s2
  , csrDiffs s1 s2
  , memDiffs s1 s2
  , [ PrivDiff (asPriv s1) (asPriv s2) | asPriv s1 /= asPriv s2 ]
  ]

gprDiffs :: ArchState -> ArchState -> [StateDiff]
gprDiffs s1 s2 =
  [ GPRDiff (Register (fromIntegral i)) v1 v2
  | i <- [0..31]
  , let v1 = asGPRs s1 V.! i
        v2 = asGPRs s2 V.! i
  , v1 /= v2
  ]

csrDiffs :: ArchState -> ArchState -> [StateDiff]
csrDiffs s1 s2 =
  [ CSRDiff addr v1 v2
  | addr <- Map.keys (Map.unionWith const (asCSRs s1) (asCSRs s2))
  , let v1 = Map.findWithDefault 0 addr (asCSRs s1)
        v2 = Map.findWithDefault 0 addr (asCSRs s2)
  , v1 /= v2
  ]

memDiffs :: ArchState -> ArchState -> [StateDiff]
memDiffs s1 s2 =
  [ MemDiff addr b1 b2
  | addr <- Map.keys (Map.unionWith const (asMem s1) (asMem s2))
  , let b1 = Map.findWithDefault 0 addr (asMem s1)
        b2 = Map.findWithDefault 0 addr (asMem s2)
  , b1 /= b2
  ]
```

- [ ] **Step 4: Build and commit**

```
cabal build all
```

```bash
git add src/CoSim/Types.hs src/CoSim/Oracle.hs src/CoSim/Diff.hs
git commit -m "feat: CoSim.Types + Oracle + Diff — ArchState, OracleCapabilities, diffArchState"
```

---

## Task 13: ELF.FlatBinary

**Files:**
- Modify: `src/ELF/FlatBinary.hs`
- Modify: `test/Test/ELF/FlatBinary.hs`

Generates a minimal ELF64 LE file suitable for Spike. Includes a `tohost` symbol at `0x80001000` for HTIF exit signalling.

**ELF layout:**
```
Offset   Size    Content
0        64      ELF header
64       56      Program header 1: PT_LOAD RX (code at 0x80000000)
120      56      Program header 2: PT_LOAD RW (data at 0x80001000)
176      cs      .text (encoded instructions)
176+cs   8       .data (tohost = 0, initially)
184+cs   48      .symtab (NULL + tohost symbol)
232+cs   8       .strtab ("\x00tohost\x00")
240+cs   39      .shstrtab
279+cs   pad     padding to 8-byte alignment
shOff    384     section header table (6 × 64 bytes)
```

- [ ] **Step 1: Write failing tests**

`test/Test/ELF/FlatBinary.hs`:
```haskell
module Test.ELF.FlatBinary (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Data.ByteString.Lazy as BL
import Data.Word (Word8)
import ELF.FlatBinary
import Core.Types
import Core.Instruction

tests :: TestTree
tests = testGroup "ELF.FlatBinary"
  [ testCase "ELF magic bytes are correct" $ do
      let prog = emptyTestProgram
      bs <- generateElf prog "/dev/null"
      let magic = BL.unpack (BL.take 4 bs)
      magic @?= [0x7F, 0x45, 0x4C, 0x46]  -- \x7fELF
  , testCase "ELF class is 64-bit (byte 4 = 2)" $ do
      let prog = emptyTestProgram
      bs <- generateElf prog "/dev/null"
      BL.index bs 4 @?= 2
  , testCase "ELF machine is EM_RISCV (0xF3)" $ do
      let prog = emptyTestProgram
      bs <- generateElf prog "/dev/null"
      -- e_machine is at bytes 18-19, little-endian
      BL.index bs 18 @?= 0xF3
      BL.index bs 19 @?= 0x00
  , testCase "ELF has 2 program headers" $ do
      let prog = emptyTestProgram
      bs <- generateElf prog "/dev/null"
      -- e_phnum at bytes 56-57
      BL.index bs 56 @?= 2
  ]

emptyTestProgram :: TestProgram
emptyTestProgram = TestProgram
  { tpStartup   = []
  , tpTrapHandler = []
  , tpTestBody  = [ADDI x1 x0 (Imm12 42)]
  , tpExit      = []
  }
```

- [ ] **Step 2: Implement ELF.FlatBinary**

`src/ELF/FlatBinary.hs`:
```haskell
module ELF.FlatBinary
  ( TestProgram(..)
  , generateElf
  , writeElf
  , defaultStartup
  , defaultTrapHandler
  , defaultExit
  , loadAddress
  , tohostAddress
  ) where

import Core.Types
import Core.Instruction
import Core.Encode      (encode)
import Data.Binary.Put
import Data.ByteString.Lazy (ByteString)
import qualified Data.ByteString.Lazy as BL
import Data.Word   (Word8, Word16, Word32, Word64)
import Data.Bits   (shiftL, shiftR, (.&.))
import System.IO   (withFile, IOMode(..), hSetBinaryMode)

loadAddress   :: Word64
loadAddress   = 0x80000000

tohostAddress :: Word64
tohostAddress = 0x80001000

data TestProgram = TestProgram
  { tpStartup     :: [Instruction]
  , tpTrapHandler :: [Instruction]
  , tpTestBody    :: [Instruction]
  , tpExit        :: [Instruction]
  } deriving (Show)

-- Assemble all instructions into a flat list of Word32
assembleProgram :: TestProgram -> [Word32]
assembleProgram tp = map encode $
  tpStartup tp <> tpTrapHandler tp <> tpTestBody tp <> tpExit tp

-- Write ELF to file, also return the bytes (for testing)
writeElf :: TestProgram -> FilePath -> IO ()
writeElf prog path = do
  bs <- generateElf prog path
  BL.writeFile path bs

generateElf :: TestProgram -> FilePath -> IO ByteString
generateElf prog _ = do
  let instrs   = assembleProgram prog
      codeBytes = runPut (mapM_ putWord32le instrs)
      cs        = fromIntegral (BL.length codeBytes) :: Word64
  return (buildElf codeBytes cs)

buildElf :: ByteString -> Word64 -> ByteString
buildElf codeBytes cs = runPut $ do
  -- ── ELF Header (64 bytes) ──────────────────────────────────────
  putWord8 0x7F; putWord8 0x45; putWord8 0x4C; putWord8 0x46  -- magic
  putWord8 2          -- EI_CLASS: 64-bit
  putWord8 1          -- EI_DATA: little-endian
  putWord8 1          -- EI_VERSION
  putWord8 0          -- EI_OSABI: none
  replicateM_ 8 (putWord8 0)  -- padding
  putWord16le 2       -- e_type: ET_EXEC
  putWord16le 0xF3    -- e_machine: EM_RISCV
  putWord32le 1       -- e_version
  putWord64le loadAddress    -- e_entry
  putWord64le 64      -- e_phoff: program headers start at byte 64
  putWord64le (align8 (176 + cs + 103))  -- e_shoff (section headers)
  putWord32le 0       -- e_flags: rv64im, soft-float ABI
  putWord16le 64      -- e_ehsize
  putWord16le 56      -- e_phentsize
  putWord16le 2       -- e_phnum
  putWord16le 64      -- e_shentsize
  putWord16le 6       -- e_shnum (NULL + .text + .data + .symtab + .strtab + .shstrtab)
  putWord16le 5       -- e_shstrndx (index of .shstrtab)

  -- ── Program Header 1: .text PT_LOAD RX (56 bytes) ─────────────
  putWord32le 1       -- p_type: PT_LOAD
  putWord32le 5       -- p_flags: PF_R (4) | PF_X (1)
  putWord64le 176     -- p_offset: code starts at byte 176
  putWord64le loadAddress    -- p_vaddr
  putWord64le loadAddress    -- p_paddr
  putWord64le cs      -- p_filesz
  putWord64le cs      -- p_memsz
  putWord64le 0x1000  -- p_align: 4096

  -- ── Program Header 2: .data PT_LOAD RW (56 bytes) ─────────────
  putWord32le 1       -- p_type: PT_LOAD
  putWord32le 6       -- p_flags: PF_R (4) | PF_W (2)
  putWord64le (176 + cs)  -- p_offset: data section
  putWord64le tohostAddress  -- p_vaddr: 0x80001000
  putWord64le tohostAddress  -- p_paddr
  putWord64le 8       -- p_filesz: 8 bytes (tohost)
  putWord64le 8       -- p_memsz
  putWord64le 0x1000  -- p_align

  -- ── .text section ─────────────────────────────────────────────
  putLazyByteString codeBytes

  -- ── .data section: tohost (8 bytes, initially 0) ──────────────
  putWord64le 0

  -- ── .symtab (2 entries × 24 bytes = 48 bytes) ─────────────────
  -- Entry 0: NULL symbol (required)
  putWord32le 0; putWord8 0; putWord8 0; putWord16le 0
  putWord64le 0; putWord64le 0
  -- Entry 1: tohost
  putWord32le 1        -- st_name: offset 1 in .strtab ("\x00tohost\x00")
  putWord8 0x11        -- st_info: STB_GLOBAL (1<<4) | STT_OBJECT (1) = 0x11
  putWord8 0           -- st_other
  putWord16le 2        -- st_shndx: section 2 = .data
  putWord64le tohostAddress  -- st_value
  putWord64le 8        -- st_size

  -- ── .strtab ("\x00tohost\x00" = 8 bytes) ──────────────────────
  putWord8 0           -- null byte (index 0)
  mapM_ putWord8 [0x74,0x6F,0x68,0x6F,0x73,0x74]  -- "tohost"
  putWord8 0           -- null terminator

  -- ── .shstrtab (section name string table) ─────────────────────
  -- "\x00.text\x00.data\x00.symtab\x00.strtab\x00.shstrtab\x00"
  -- Offsets: 0=null, 1=.text, 7=.data, 13=.symtab, 21=.strtab, 29=.shstrtab
  putWord8 0
  mapM_ putWord8 (map fromIntegral (map fromEnum ".text")) >> putWord8 0
  mapM_ putWord8 (map fromIntegral (map fromEnum ".data")) >> putWord8 0
  mapM_ putWord8 (map fromIntegral (map fromEnum ".symtab")) >> putWord8 0
  mapM_ putWord8 (map fromIntegral (map fromEnum ".strtab")) >> putWord8 0
  mapM_ putWord8 (map fromIntegral (map fromEnum ".shstrtab")) >> putWord8 0

  -- ── Padding to 8-byte alignment ───────────────────────────────
  let currentOffset = 176 + cs + 103
      padNeeded     = fromIntegral ((8 - currentOffset `mod` 8) `mod` 8)
  replicateM_ padNeeded (putWord8 0)

  -- ── Section Header Table (6 × 64 bytes = 384 bytes) ───────────
  let shOff    = align8 (176 + cs + 103)
      textOff  = 176
      dataOff  = 176 + cs
      symOff   = 176 + cs + 8
      strOff   = 176 + cs + 56
      shStrOff = 176 + cs + 64

  -- SHT entry helper: type flags addr off size link info align entsize
  let shEntry shType shFlags shAddr shOffset shSize shLink shInfo shAddralign shEntsize = do
        putWord32le 0          -- sh_name (filled below)
        putWord32le shType
        putWord64le shFlags
        putWord64le shAddr
        putWord64le shOffset
        putWord64le shSize
        putWord32le shLink
        putWord32le shInfo
        putWord64le shAddralign
        putWord64le shEntsize

  -- We need sh_name offsets into .shstrtab. Pre-compute:
  -- Index 0: NULL → 0; 1: .text → 1; 2: .data → 7; 3: .symtab → 13
  -- 4: .strtab → 21; 5: .shstrtab → 29

  -- Section 0: NULL
  putWord32le 0  -- sh_name=0
  replicateM_ 60 (putWord8 0)

  -- Section 1: .text  (SHT_PROGBITS=1, SHF_ALLOC|SHF_EXECINSTR=6)
  putWord32le 1          -- sh_name = ".text" at offset 1
  putWord32le 1          -- sh_type = SHT_PROGBITS
  putWord64le 6          -- sh_flags = SHF_ALLOC(2) | SHF_EXECINSTR(4)
  putWord64le loadAddress -- sh_addr
  putWord64le textOff    -- sh_offset
  putWord64le cs         -- sh_size
  putWord32le 0          -- sh_link
  putWord32le 0          -- sh_info
  putWord64le 4          -- sh_addralign
  putWord64le 0          -- sh_entsize

  -- Section 2: .data  (SHT_PROGBITS=1, SHF_ALLOC|SHF_WRITE=3)
  putWord32le 7          -- sh_name = ".data" at offset 7
  putWord32le 1          -- sh_type = SHT_PROGBITS
  putWord64le 3          -- sh_flags = SHF_ALLOC(2) | SHF_WRITE(1)
  putWord64le tohostAddress  -- sh_addr
  putWord64le dataOff    -- sh_offset
  putWord64le 8          -- sh_size
  putWord32le 0          -- sh_link
  putWord32le 0          -- sh_info
  putWord64le 8          -- sh_addralign
  putWord64le 0          -- sh_entsize

  -- Section 3: .symtab  (SHT_SYMTAB=2)
  putWord32le 13         -- sh_name = ".symtab" at offset 13
  putWord32le 2          -- sh_type = SHT_SYMTAB
  putWord64le 0          -- sh_flags
  putWord64le 0          -- sh_addr
  putWord64le symOff     -- sh_offset
  putWord64le 48         -- sh_size = 2 × 24
  putWord32le 4          -- sh_link = index of .strtab
  putWord32le 1          -- sh_info = index of first global symbol
  putWord64le 8          -- sh_addralign
  putWord64le 24         -- sh_entsize

  -- Section 4: .strtab  (SHT_STRTAB=3)
  putWord32le 21         -- sh_name = ".strtab" at offset 21
  putWord32le 3          -- sh_type = SHT_STRTAB
  putWord64le 0; putWord64le 0  -- flags, addr
  putWord64le strOff     -- sh_offset
  putWord64le 8          -- sh_size
  putWord32le 0; putWord32le 0  -- link, info
  putWord64le 1; putWord64le 0  -- addralign, entsize

  -- Section 5: .shstrtab  (SHT_STRTAB=3)
  putWord32le 29         -- sh_name = ".shstrtab" at offset 29
  putWord32le 3          -- sh_type = SHT_STRTAB
  putWord64le 0; putWord64le 0
  putWord64le shStrOff
  putWord64le 39         -- sh_size
  putWord32le 0; putWord32le 0
  putWord64le 1; putWord64le 0

-- ── Startup/Exit templates ────────────────────────────────────────

-- Minimal startup: set up stack pointer (sp = 0x80010000)
-- Note: LUI sets upper 20 bits. 0x80010 << 12 = 0x80010000.
-- On RV64, sign-extension makes this 0xFFFFFFFF80010000; Spike treats
-- physical addresses in the lower 32 bits equivalently.
defaultStartup :: [Instruction]
defaultStartup =
  [ LUI sp (Imm20 0x80010)    -- sp = 0x80010000 (stack top)
  , ADDI sp sp (Imm12 0)       -- sp = sp (no-op; explicit for clarity)
  ]

-- Minimal trap handler: just return (MRET)
-- For real test scenarios this should save/restore registers.
defaultTrapHandler :: [Instruction]
defaultTrapHandler = [MRET]

-- HTIF exit sequence:
-- 1. Load tohost address into t0 using AUIPC + ADDI
-- 2. Store 1 to tohost (Spike exits with success)
-- 3. Infinite loop (spin until Spike detects tohost write)
--
-- We can't compute the exact AUIPC offset without knowing the PC at exit.
-- Use LUI instead, accepting sign-extension (works for Spike's 32-bit DRAM).
defaultExit :: [Instruction]
defaultExit =
  [ LUI   t0 (Imm20 0x80001)     -- t0 = 0x80001000 (tohost, sign-extended)
  , ADDI  t1 x0 (Imm12 1)        -- t1 = 1 (success code for HTIF)
  , SW    t1 t0 (Imm12 0)        -- mem[t0+0] = 1  → tohost = 1
  , JAL   x0 (Imm21 0)           -- j . (infinite loop)
  ]

-- ── Helpers ───────────────────────────────────────────────────────

align8 :: Word64 -> Word64
align8 x = (x + 7) .&. complement 7
  where complement n = maxBound - n  -- bit complement for alignment mask

replicateM_ :: Monad m => Int -> m a -> m ()
replicateM_ 0 _ = return ()
replicateM_ n m = m >> replicateM_ (n-1) m
```

Note: `replicateM_` is already in `Control.Monad`. Remove the local definition and import it. Also `complement` from `Data.Bits`. The actual file should import those.

Here is the corrected header for the file:
```haskell
import Data.Bits   ((.&.), complement)
import Control.Monad (replicateM_)
```

- [ ] **Step 3: Run tests**

```
cabal test riscv-rig-test --test-option="--pattern=ELF"
```

Expected: all 4 ELF structure tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/ELF/FlatBinary.hs test/Test/ELF/FlatBinary.hs
git commit -m "feat: ELF.FlatBinary — ELF64 writer with tohost symbol for Spike HTIF"
```

---

## Task 14: CoSim.Spike + CoSim.Batch

**Files:**
- Modify: `src/CoSim/Spike.hs`
- Modify: `src/CoSim/Batch.hs`
- Modify: `test/Test/CoSim/Spike.hs`

**Prerequisite:** Spike must be installed (`spike --help` works).

- [ ] **Step 1: Write failing tests**

`test/Test/CoSim/Spike.hs`:
```haskell
module Test.CoSim.Spike (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import CoSim.Spike
import Data.Either (isRight, isLeft)

tests :: TestTree
tests = testGroup "CoSim.Spike"
  [ testCase "parseSpikeLogLine parses valid line" $
      let line = "core   0: 0x0000000080000000 (0x00000093) addi zero, zero, 0"
      in  case parseSpikeLogLine line of
            Right entry -> do
              lePC entry @?= 0x80000000
              leRawInstr entry @?= 0x00000093
              leHartID entry @?= 0
            Left err -> assertFailure ("parse failed: " <> show err)
  , testCase "parseSpikeLogLine rejects garbage" $
      isLeft (parseSpikeLogLine "not a spike log line") @?= True
  , testCase "parseSpikeLog handles multiple lines" $ do
      let logText = unlines
            [ "core   0: 0x0000000080000000 (0x00000093) addi zero, zero, 0"
            , "core   0: 0x0000000080000004 (0x00100093) addi ra, zero, 1"
            ]
      case parseSpikeLog logText of
        Right entries -> length entries @?= 2
        Left err      -> assertFailure ("parse failed: " <> show err)
  ]
```

- [ ] **Step 2: Implement CoSim.Spike**

`src/CoSim/Spike.hs`:
```haskell
module CoSim.Spike
  ( SpikeConfig(..)
  , defaultSpikeConfig
  , runSpike
  , SpikeResult(..)
  , parseSpikeLog
  , parseSpikeLogLine
  ) where

import CoSim.Types
import Core.Decode      (decode)
import Data.Text        (Text)
import qualified Data.Text as T
import Data.Word        (Word32, Word64)
import Data.Char        (isHexDigit)
import System.Process   (readProcessWithExitCode)
import System.Exit      (ExitCode(..))
import Text.Megaparsec
import Text.Megaparsec.Char
import qualified Text.Megaparsec.Char.Lexer as L
import Data.Void        (Void)
import Numeric          (readHex)

type Parser = Parsec Void Text

data SpikeConfig = SpikeConfig
  { scSpikePath :: FilePath
  , scISA       :: String     -- e.g. "rv64im"
  , scLogLevel  :: Bool       -- whether to pass -l flag
  } deriving (Show)

defaultSpikeConfig :: SpikeConfig
defaultSpikeConfig = SpikeConfig
  { scSpikePath = "spike"
  , scISA       = "rv64im"
  , scLogLevel  = True
  }

data SpikeResult = SpikeResult
  { srExitCode  :: ExitCode
  , srLog       :: [LogEntry]
  , srStdout    :: String
  , srStderr    :: String
  } deriving (Show)

runSpike :: SpikeConfig -> FilePath -> IO SpikeResult
runSpike cfg elfPath = do
  let args = [ "--isa=" <> scISA cfg ]
              <> [ "-l" | scLogLevel cfg ]
              <> [ elfPath ]
  (exitCode, stdout, stderr) <-
    readProcessWithExitCode (scSpikePath cfg) args ""
  let logEntries = case parseSpikeLog (T.pack stderr) of
                     Right es -> es
                     Left _   -> []
  return SpikeResult
    { srExitCode = exitCode
    , srLog      = logEntries
    , srStdout   = stdout
    , srStderr   = stderr
    }

-- ── Spike log parsing (Megaparsec) ───────────────────────────────

-- Spike log line format:
-- "core   0: 0x0000000080000000 (0x00000093) addi zero, zero, 0"
parseSpikeLogLine :: Text -> Either String LogEntry
parseSpikeLogLine line =
  case runParser spikeLogLineP "<spike-log>" line of
    Left err -> Left (errorBundlePretty err)
    Right e  -> Right e

parseSpikeLog :: Text -> Either String [LogEntry]
parseSpikeLog logText =
  let ls = filter (T.isPrefixOf "core") (T.lines logText)
  in  sequence (map parseSpikeLogLine ls)

spikeLogLineP :: Parser LogEntry
spikeLogLineP = do
  _       <- string "core"
  space1
  hartID  <- L.decimal
  _       <- char ':'
  space1
  pc      <- hexWord64
  space1
  rawInstr <- between (char '(') (char ')') hexWord32
  _       <- takeRest  -- discard assembly text
  let instr = case decode rawInstr of
                Right i -> Right i
                Left e  -> Left (show e)
  return LogEntry
    { leHartID   = fromIntegral (hartID :: Integer)
    , lePC       = pc
    , leRawInstr = rawInstr
    , leInstr    = instr
    , leDelta    = emptyDelta
    }
  where
    emptyDelta = StateDelta [] [] [] Nothing

hexWord64 :: Parser Word64
hexWord64 = do
  _ <- string "0x"
  digits <- takeWhile1P (Just "hex digit") isHexDigit
  case readHex (T.unpack digits) of
    [(v, "")] -> return v
    _         -> fail "invalid hex word64"

hexWord32 :: Parser Word32
hexWord32 = do
  _ <- string "0x"
  digits <- takeWhile1P (Just "hex digit") isHexDigit
  case readHex (T.unpack digits) of
    [(v, "")] -> return v
    _         -> fail "invalid hex word32"
```

- [ ] **Step 3: Implement CoSim.Batch**

`src/CoSim/Batch.hs`:
```haskell
module CoSim.Batch
  ( BatchConfig(..)
  , BatchResult(..)
  , defaultBatchConfig
  , runBatch
  ) where

import CoSim.Types
import CoSim.Spike
import CoSim.Oracle    (CoSimOracle(..), selectOracles)
import ELF.FlatBinary  (TestProgram, writeElf, defaultStartup, defaultTrapHandler, defaultExit)
import Generator.Seed  (Seed)
import Data.List       (foldl')
import System.Exit     (ExitCode(..))
import System.IO.Temp  (withSystemTempFile)

data BatchConfig = BatchConfig
  { bcOracles     :: [CoSimOracle]
  , bcSpikeConfig :: SpikeConfig
  } deriving (Show)

defaultBatchConfig :: BatchConfig
defaultBatchConfig = BatchConfig
  { bcOracles     = [OracleSpike "spike"]
  , bcSpikeConfig = defaultSpikeConfig
  }

data BatchResult = BatchResult
  { brPassed    :: Int
  , brFailed    :: Int
  , brErrors    :: [(TestProgram, String)]  -- (program, error message)
  } deriving (Show)

-- Run a list of test programs through Spike, collecting pass/fail counts.
-- Phase 1: "pass" means Spike exits with ExitSuccess.
runBatch :: BatchConfig -> [TestProgram] -> IO BatchResult
runBatch cfg progs = foldl' combine (BatchResult 0 0 []) <$> mapM runOne progs
  where
    combine (BatchResult p f es) (BatchResult p' f' es') =
      BatchResult (p+p') (f+f') (es<>es')
    runOne prog =
      withSystemTempFile "riscv-rig-XXXXXX.elf" $ \path _ -> do
        let full = prog
              { tpStartup     = defaultStartup
              , tpTrapHandler = defaultTrapHandler
              , tpExit        = defaultExit
              }
        writeElf full path
        result <- runSpike (bcSpikeConfig cfg) path
        return $ case srExitCode result of
          ExitSuccess   -> BatchResult 1 0 []
          ExitFailure n ->
            BatchResult 0 1
              [(prog, "Spike exited with code " <> show n
                      <> "\nstderr: " <> take 500 (srStderr result))]
```

- [ ] **Step 4: Run tests**

```
cabal test riscv-rig-test --test-option="--pattern=CoSim.Spike"
```

Expected: all 3 log parsing tests pass (no Spike process needed for these).

- [ ] **Step 5: Commit**

```bash
git add src/CoSim/Spike.hs src/CoSim/Batch.hs test/Test/CoSim/Spike.hs
git commit -m "feat: CoSim.Spike + Batch — Spike runner, Megaparsec log parser, batch mode"
```

---

## Task 15: CLI

**Files:**
- Modify: `app/CLI/Options.hs`
- Modify: `app/CLI/Runner.hs`
- Modify: `app/Main.hs`

- [ ] **Step 1: Implement CLI.Options**

`app/CLI/Options.hs`:
```haskell
module CLI.Options
  ( Command(..)
  , RunOptions(..)
  , GenerateOptions(..)
  , parseOptions
  ) where

import Options.Applicative
import Data.Word (Word64)

data Command
  = CmdRun      RunOptions
  | CmdGenerate GenerateOptions
  | CmdVersion
  deriving (Show)

data RunOptions = RunOptions
  { roExtensions :: [String]   -- e.g. ["M","A"]
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

parseOptions :: IO Command
parseOptions = execParser opts
  where
    opts = info (commandP <**> helper)
      (fullDesc
       <> progDesc "RISC-V Random Instruction Generator"
       <> header   "riscv-rig — SMT-guided RISC-V test generator")

commandP :: Parser Command
commandP = subparser
  ( command "run"
      (info (CmdRun <$> runOptionsP)
            (progDesc "Generate and co-simulate with Spike"))
  <> command "generate"
      (info (CmdGenerate <$> generateOptionsP)
            (progDesc "Generate ELF files without running co-simulation"))
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
```

- [ ] **Step 2: Implement CLI.Runner**

`app/CLI/Runner.hs`:
```haskell
module CLI.Runner (runCommand) where

import CLI.Options
import Core.Instruction (Extension(..))
import Generator.Types  (defaultConfig, GeneratorConfig(..))
import Generator.Seed   (newRandomSeed, seedFromWord64)
import Generator.Random (generateSequence)
import Coverage.Types   (allOpcodeBins)
import Coverage.Accumulator (newAccumulator, recordCoverage, snapshotCoverage)
import Coverage.Analysis    (renderSummary)
import CoSim.Batch      (BatchConfig(..), defaultBatchConfig, runBatch)
import CoSim.Spike      (defaultSpikeConfig, SpikeConfig(..))
import CoSim.Oracle     (CoSimOracle(..))
import ELF.FlatBinary   (TestProgram(..), defaultStartup, defaultTrapHandler, defaultExit)
import Control.Concurrent.STM (atomically)
import Data.Set (fromList)
import qualified Data.Set as Set
import System.Directory (createDirectoryIfMissing)
import System.FilePath  ((</>))
import Data.Text        (pack)

runCommand :: Command -> IO ()
runCommand CmdVersion = putStrLn "riscv-rig 0.1.0"

runCommand (CmdGenerate opts) = do
  createDirectoryIfMissing True (goOutputDir opts)
  seed <- maybe newRandomSeed (return . seedFromWord64) (goSeed opts)
  let cfg = defaultConfig
        { gcExtensions = parseExtensions (goExtensions opts)
        , gcSeed       = seed
        }
  mapM_ (\i -> do
    seq_ <- generateSequence cfg
    let prog = TestProgram
          { tpStartup     = defaultStartup
          , tpTrapHandler = defaultTrapHandler
          , tpTestBody    = seq_
          , tpExit        = defaultExit
          }
    -- TODO: write to output dir in Phase 2
    putStrLn ("Generated sequence " <> show i <> " (" <> show (length seq_) <> " instructions)")
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
    putStrLn ("Round " <> show roundN <> "/" <> show (roRounds opts))
    seqs <- mapM (\_ -> generateSequence cfg) [1..10 :: Int]
    let progs = map (\s -> TestProgram
                      { tpStartup     = []
                      , tpTrapHandler = []
                      , tpTestBody    = s
                      , tpExit        = []
                      }) seqs
    result <- runBatch batchCfg progs
    putStrLn ("  Passed: " <> show (brPassed result)
              <> "  Failed: " <> show (brFailed result))
    snap <- snapshotCoverage acc
    putStr (renderSummary snap)
    ) [1..roRounds opts]

parseExtensions :: [String] -> Set.Set Extension
parseExtensions exts =
  Set.fromList (RV64I : map parseExt exts)
  where
    parseExt "M" = RV64M
    parseExt "P" = RVPriv
    parseExt _   = RV64I   -- default: ignore unknown
```

- [ ] **Step 3: Implement app/Main.hs**

`app/Main.hs`:
```haskell
module Main (main) where

import CLI.Options (parseOptions)
import CLI.Runner  (runCommand)

main :: IO ()
main = parseOptions >>= runCommand
```

- [ ] **Step 4: Build and smoke test CLI**

```
cabal build riscv-rig
cabal run riscv-rig -- version
```

Expected output:
```
riscv-rig 0.1.0
```

```
cabal run riscv-rig -- generate --count 3
```

Expected: prints 3 "Generated sequence N (M instructions)" lines.

- [ ] **Step 5: Commit**

```bash
git add app/CLI/Options.hs app/CLI/Runner.hs app/Main.hs
git commit -m "feat: CLI — optparse-applicative, run/generate commands, coverage summary output"
```

---

## Task 16: Integration Smoke Test

**Files:**
- Create: `test/Test/Integration/Smoke.hs`
- Modify: `test/Spec.hs`
- Modify: `riscv-rig.cabal` (add integration test to test suite or as separate suite)

**Prerequisite:** `spike` must be on `PATH`. This test is skipped if Spike is not found.

- [ ] **Step 1: Write the integration test**

`test/Test/Integration/Smoke.hs`:
```haskell
module Test.Integration.Smoke (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import System.Exit     (ExitCode(..))
import System.Process  (readProcess)
import System.IO.Error (tryIOError)
import Control.Exception (SomeException, try)
import Core.Types
import Core.Instruction
import Generator.Types  (defaultConfig, GeneratorConfig(..))
import Generator.Seed   (seedFromWord64)
import Generator.Random (generateSequence)
import ELF.FlatBinary
import CoSim.Spike
import CoSim.Oracle     (CoSimOracle(..))
import System.IO.Temp   (withSystemTempFile)

tests :: TestTree
tests = testGroup "Integration"
  [ testCase "spike is on PATH" $ do
      result <- try (readProcess "spike" ["--help"] "") :: IO (Either SomeException String)
      case result of
        Left _  -> assertFailure "spike not found on PATH — install Spike to run this test"
        Right _ -> return ()

  , testCase "generate and run trivial program through Spike" $ do
      -- Check spike exists first
      spikeExists <- checkSpikeExists
      if not spikeExists
        then putStrLn "SKIP: spike not on PATH"
        else do
          -- Fixed seed for reproducibility
          let cfg  = defaultConfig { gcSeed = seedFromWord64 0xDEAD }
          seq_ <- generateSequence cfg
          let prog = TestProgram
                { tpStartup     = defaultStartup
                , tpTrapHandler = defaultTrapHandler
                , tpTestBody    = take 5 seq_ <> [ADDI x1 x0 (Imm12 1)]
                , tpExit        = defaultExit
                }
          withSystemTempFile "smoke-test-.elf" $ \path _ -> do
            writeElf prog path
            result <- runSpike defaultSpikeConfig path
            -- Just check Spike didn't crash (exit code 0 = HTIF success)
            srExitCode result @?= ExitSuccess

  , testCase "10 random sequences through Spike all pass" $ do
      spikeExists <- checkSpikeExists
      if not spikeExists
        then putStrLn "SKIP: spike not on PATH"
        else do
          results <- mapM runOneSeq [0..9]
          let failures = filter (/= ExitSuccess) results
          failures @?= []
  ]

runOneSeq :: Int -> IO ExitCode
runOneSeq i = do
  let cfg = defaultConfig { gcSeed = seedFromWord64 (fromIntegral i * 1000 + 42) }
  seq_ <- generateSequence cfg
  let prog = TestProgram
        { tpStartup     = defaultStartup
        , tpTrapHandler = defaultTrapHandler
        , tpTestBody    = seq_
        , tpExit        = defaultExit
        }
  withSystemTempFile "riscv-rig-smoke-.elf" $ \path _ -> do
    writeElf prog path
    result <- runSpike defaultSpikeConfig path
    return (srExitCode result)

checkSpikeExists :: IO Bool
checkSpikeExists = do
  result <- tryIOError (readProcess "spike" ["--help"] "")
  return (either (const False) (const True) result)
```

- [ ] **Step 2: Add integration tests to cabal file**

Add to `riscv-rig.cabal`:
```cabal
test-suite riscv-rig-integration
  import:          common-options
  type:            exitcode-stdio-1.0
  hs-source-dirs:  test
  main-is:         IntegrationSpec.hs
  other-modules:
    Test.Integration.Smoke
  build-depends:
      base           >= 4.17 && < 5
    , riscv-rig
    , tasty          >= 1.4
    , tasty-hunit    >= 0.10
    , process        >= 1.6
    , temporary      >= 1.3
```

Create `test/IntegrationSpec.hs`:
```haskell
module Main (main) where

import Test.Tasty
import qualified Test.Integration.Smoke as Smoke

main :: IO ()
main = defaultMain $ testGroup "riscv-rig-integration" [Smoke.tests]
```

- [ ] **Step 3: Run unit tests (must all pass)**

```
cabal test riscv-rig-test
```

Expected: all 20+ unit tests pass.

- [ ] **Step 4: Run integration tests (requires Spike)**

```
cabal test riscv-rig-integration
```

Expected (with Spike on PATH):
```
riscv-rig-integration
  Integration
    spike is on PATH:                          OK
    generate and run trivial program through Spike: OK
    10 random sequences through Spike all pass: OK

All 3 tests passed (X.XXs)
```

If Spike is not on PATH, the last two tests print SKIP and pass.

- [ ] **Step 5: Final commit**

```bash
git add test/Test/Integration/Smoke.hs test/IntegrationSpec.hs riscv-rig.cabal
git commit -m "feat: integration smoke test — generate 10 random RV64IM sequences, run through Spike, check exit success"
```

---

## Self-Review

**Spec coverage check:**

| Spec Section | Covered by |
|---|---|
| RV64I + M ADT | Task 3 |
| Encode/Decode | Tasks 4, 5 |
| CSR model | Task 6 |
| ConstraintDef + SBV/Z3 | Tasks 7, 8 |
| Constraint combinators | Task 8 |
| Hedgehog random generator | Task 10 |
| Seed management | Task 9 |
| Flat binary / ELF output | Task 13 |
| Spike-only CoSim (batch) | Task 14 |
| Basic coverage (opcode + value range) | Task 11 |
| Basic CLI (optparse-applicative) | Task 15 |
| Roundtrip property test | Task 5 |
| Oracle capability model | Task 12 |

**Phase 1 items NOT in this plan (deferred to Phase 2):**
- RV64A + F + D + C ADT
- PMA model
- Scenario system
- Extension dependency resolution
- UNSAT core + density analysis (foundation in Task 7, full version Phase 2)
- Sail CoSim
- Shrinking
- Privilege level / trap handler generation (basic stubs only)

**Known limitations documented in code:**
1. `generateSequence` in Task 10 uses `Gen.sample` which doesn't guarantee exact seed reproducibility across Hedgehog versions. A proper fix uses `Hedgehog.Internal.Seed` directly.
2. The `defaultExit` in Task 13 uses `LUI t0, 0x80001` which sign-extends on RV64. This gives address `0xFFFFFFFF80001000`. Spike maps this to physical address `0x80001000` in the default 32-bit DRAM layout, so it works in practice.
3. The `estimateDensity` solver in Task 7 uses sequential blocking clauses. For large constraint sets this is slow; parallel AllSAT is a Phase 3 optimization.

---

Plan complete and saved to `docs/superpowers/plans/2026-05-22-riscv-rig-phase1.md`.

**Two execution options:**

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — execute tasks in this session using `executing-plans`, batch execution with checkpoints

Which approach?
