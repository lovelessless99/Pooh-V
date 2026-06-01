module Coverage.Types
  ( CoverageBin(..)
  , CoverageMap
  , HitCount
  , SequencePattern(..)
  , ValueCategory(..)
  , allOpcodeBins
  , allCoverageBins
  ) where

import Data.Map.Strict (Map)
import Data.Text       (Text)
import Core.Types      (PrivilegeLevel(..))
import GHC.Generics    (Generic)

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

-- Subset of opcodes meaningful at privilege-level coverage
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
