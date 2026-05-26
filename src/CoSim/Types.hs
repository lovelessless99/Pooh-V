module CoSim.Types
  ( ArchState(..)
  , StateDelta(..)
  , StateDiff(..)
  , LogEntry(..)
  , MismatchReport(..)
  , emptyArchState
  ) where

import Core.Types       (Register, PrivilegeLevel(..))
import Core.Instruction (Instruction)
import Generator.Seed   (Seed)
import Data.Map.Strict  (Map)
import qualified Data.Map.Strict as Map
import Data.Vector      (Vector)
import qualified Data.Vector as V
import Data.Word        (Word8, Word16, Word32, Word64)

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
  { sdRegWrites  :: [(Register, Word64)]
  , sdMemWrites  :: [(Word64, Word8)]
  , sdCSRWrites  :: [(Word16, Word64)]
  , sdPrivChange :: Maybe PrivilegeLevel
  } deriving (Show, Eq)

-- A difference between two oracles at the same instruction step
data StateDiff
  = PCDiff  { diffOrcl1PC   :: Word64, diffOrcl2PC   :: Word64 }
  | GPRDiff { diffReg       :: Register
            , diffOrcl1Val  :: Word64,  diffOrcl2Val  :: Word64 }
  | CSRDiff { diffCSRAddr   :: Word16
            , diffOrcl1Val  :: Word64,  diffOrcl2Val  :: Word64 }
  | MemDiff { diffAddr      :: Word64
            , diffOrcl1Byte :: Word8,   diffOrcl2Byte :: Word8 }
  | PrivDiff { diffOrcl1Priv :: PrivilegeLevel
             , diffOrcl2Priv :: PrivilegeLevel }
  deriving (Show, Eq)

data LogEntry = LogEntry
  { leHartID   :: Int
  , lePC       :: Word64
  , leRawInstr :: Word32
  , leInstr    :: Either String Instruction  -- Right if decode succeeded
  , leDelta    :: StateDelta
  } deriving (Show)

data MismatchReport = MismatchReport
  { mrSeed        :: Seed
  , mrPC          :: Word64
  , mrInstruction :: Instruction
  , mrDiffs       :: [StateDiff]
  , mrContext     :: [LogEntry]  -- last N log entries before mismatch
  } deriving (Show)
