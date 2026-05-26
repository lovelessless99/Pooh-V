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
