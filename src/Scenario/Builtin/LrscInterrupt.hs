module Scenario.Builtin.LrscInterrupt (spec) where

import Scenario.Types
import Core.Types       (AqRl(..), x1, x2)
import Core.Instruction (Extension(..), Instruction(..))
import Coverage.Types   (CoverageBin(..), SequencePattern(..))
import Constraint.Types (emptyConstraintSet)

spec :: ScenarioSpec
spec = ScenarioSpec
  { sName        = "lrsc-timer-interrupt"
  , sTags        = [Atomic, Interrupt, Privileged, CornerCase]
  , sDescription =
      "LR.D/SC.D pair with a timer interrupt injected between them. \
      \Tests whether the reservation is correctly invalidated. \
      \SC.D should fail (rd = 1) because the interrupt breaks the reservation."
  , sExtensions  = [RV64A, RVPriv]
  , sClaims      =
      [ PatternBin LrscPair
      , PatternBin LrscFail
      ]
  , sPhases      =
      [ emptyPhase "setup"
      , ScenarioPhase
          { spName        = "lr-acquire"
          , spConstraints = emptyConstraintSet
          , spDirectives  =
              [ EmitInstr (LR_D x1 x2 AqRlAcquire)
              , RandomN 0 3
              ]
          , spEvents      = []
          }
      , ScenarioPhase
          { spName        = "interrupt-injection"
          , spConstraints = emptyConstraintSet
          , spDirectives  = []
          , spEvents      = [InjectTimerInterrupt]
          }
      , ScenarioPhase
          { spName        = "sc-verify"
          , spConstraints = emptyConstraintSet
          , spDirectives  =
              [ EmitInstr (SC_D x1 x2 x1 AqRlRelease)
              ]
          , spEvents      = []
          }
      ]
  }
