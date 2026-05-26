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
import qualified Hedgehog.Gen            as Gen
import qualified Hedgehog.Range          as Range
import qualified Hedgehog.Internal.Seed  as HSeed
import qualified Hedgehog.Internal.Gen   as HGen
import qualified Hedgehog.Internal.Tree  as HTree
import qualified Data.Set as Set

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

genUImm6 :: Gen UImm6
genUImm6 = UImm6 <$> Gen.word8 (Range.linear 0 63)

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
  , SLLI  <$> genReg <*> genReg <*> genUImm6   -- RV64I: 6-bit shamt
  , SRLI  <$> genReg <*> genReg <*> genUImm6
  , SRAI  <$> genReg <*> genReg <*> genUImm6
  , SLLIW <$> genReg <*> genReg <*> genUImm5   -- word shifts: 5-bit
  , SRLIW <$> genReg <*> genReg <*> genUImm5
  , SRAIW <$> genReg <*> genReg <*> genUImm5
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

-- Generate a sequence of instructions deterministically from gcSeed.
generateSequence :: GeneratorConfig -> IO InstrSequence
generateSequence cfg = do
  let w64   = unSeed (gcSeed cfg)
      hSeed = HSeed.from w64
      exts  = Set.toList (gcExtensions cfg)
      n     = gcMinLength cfg + fromIntegral
                (w64 `mod` fromIntegral (gcMaxLength cfg - gcMinLength cfg + 1))
      gen   = Gen.list (Range.singleton n) (genInstruction exts)
  case HGen.evalGen (fromIntegral n) hSeed gen of
    Nothing   -> return []
    Just tree -> return (HTree.treeValue tree)
