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
  , addConstraint
  ) where

import Core.Instruction (Extension)
import Data.SBV hiding (ConstraintSet)
import Data.Text    (Text)
import GHC.Generics (Generic)

data Tag
  = Memory | Alignment | Register | SafetyNet | Branch | Atomic
  | Privilege | FP | Performance | CornerCase
  deriving (Show, Eq, Ord, Enum, Bounded, Generic)

data SymInstrParams = SymInstrParams
  { symOpcode :: SWord8
  , symRd     :: SWord8
  , symRs1    :: SWord8
  , symRs2    :: SWord8
  , symFunct3 :: SWord8
  , symFunct7 :: SWord8
  , symImm    :: SInt32
  }

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

addConstraint :: ConstraintDef -> ConstraintSet -> ConstraintSet
addConstraint c (ConstraintSet cs) = ConstraintSet (c : cs)

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
  | Infeasible [Text]
  | FeasibilityUnknown Text
  deriving (Show, Eq)
