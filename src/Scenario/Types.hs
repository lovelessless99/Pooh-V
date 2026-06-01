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

data Event
  = InjectTimerInterrupt
  | InjectSoftwareInterrupt
  | SetPrivilege PrivilegeLevel
  | FlushTLB
  | FlushCache
  deriving (Show, Eq, Generic)

data Directive
  = EmitInstr Instruction
  | RandomN   Int Int
  | UseConstraintNamed Text
  deriving (Show, Eq, Generic)

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

data ScenarioSpec = ScenarioSpec
  { sName        :: Text
  , sTags        :: [Tag]
  , sDescription :: Text
  , sExtensions  :: [Extension]
  , sClaims      :: [CoverageBin]
  , sPhases      :: [ScenarioPhase]
  } deriving (Generic)
