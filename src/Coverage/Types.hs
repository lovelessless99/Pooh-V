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
import qualified Data.Text as T
import Core.Types      (PrivilegeLevel(..))
import Core.Instruction (Instruction)
import GHC.Generics    (Generic, Rep, C1, D1, (:+:), Constructor, conName)
import Data.Proxy      (Proxy(..))

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

-- GHC.Generics auto-derive: new constructors automatically appear here.
-- Walk the generic Rep tree and collect all constructor names.
class GConNames (f :: * -> *) where
  gConNamesList :: Proxy f -> [String]

instance (GConNames f, GConNames g) => GConNames (f :+: g) where
  gConNamesList _ = gConNamesList (Proxy :: Proxy f)
                 <> gConNamesList (Proxy :: Proxy g)

instance Constructor c => GConNames (C1 c f) where
  gConNamesList _ = [conName (undefined :: C1 c f ())]

instance GConNames f => GConNames (D1 c f) where
  gConNamesList _ = gConNamesList (Proxy :: Proxy f)

allOpcodeBins :: [CoverageBin]
allOpcodeBins = map (OpcodeBin . T.pack) $
  gConNamesList (Proxy :: Proxy (Rep Instruction))

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
