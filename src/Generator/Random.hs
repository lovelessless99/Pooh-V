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
  | AtomicOp    -- RV64A: LR/SC/AMO
  | FloatSOp    -- RV64F: single-precision FP
  | FloatDOp    -- RV64D: double-precision FP
  | CompressOp  -- RV64C: compressed
  deriving (Show, Eq, Ord, Enum, Bounded)

availableOpcodes :: [Extension] -> [OpcodeCategory]
availableOpcodes exts =
  [ AluR, AluI, LoadOp, StoreOp, BranchOp, JumpOp, UpperImm, SystemOp ]
  <> [ MulDiv     | RV64M `elem` exts ]
  <> [ PrivOp     | RVPriv `elem` exts ]
  <> [ AtomicOp   | RV64A `elem` exts ]
  <> [ FloatSOp   | RV64F `elem` exts ]
  <> [ FloatDOp   | RV64D `elem` exts ]
  <> [ CompressOp | RV64C `elem` exts ]

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
    AtomicOp  -> genAtomic
    FloatSOp  -> genFloatS
    FloatDOp  -> genFloatD
    CompressOp -> genCompress

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

-- ── RV64A/F/D/C helpers ───────────────────────────────────────────

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

genImm9_ :: Gen Imm9
genImm9_ = Imm9 <$> Gen.int16 (Range.linearFrom 0 (-256) 254)

genImm10_ :: Gen Imm10
genImm10_ = Imm10 <$> Gen.int16 (Range.linearFrom 0 (-512) 496)

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
genCReg :: Gen Register
genCReg = Register <$> Gen.word8 (Range.linear 8 15)

genCompress :: Gen Instruction
genCompress = do
  rd   <- genNonZeroReg; rs1 <- genNonZeroReg; rs2 <- genNonZeroReg
  rd'  <- genCReg;       rs1' <- genCReg;       rs2' <- genCReg
  imm6 <- genImm6
  u7   <- genUImm7;   u8 <- genUImm8
  u9   <- genUImm9;   u10 <- genUImm10
  imm9_ <- genImm9_;  imm10_ <- genImm10_
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
