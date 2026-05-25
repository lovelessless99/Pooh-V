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
