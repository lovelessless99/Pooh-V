module Test.Constraint.Solver (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Core.Types ()
import Constraint.Types
import Constraint.Solver
import Data.SBV                ((.==), (./=))

tests :: TestTree
tests = testGroup "Constraint.Solver"
  [ testCase "empty constraint set is satisfiable" $ do
      result <- solve emptyConstraintSet
      case result of
        Just _  -> return ()
        Nothing -> assertFailure "expected a solution"
  , testCase "infeasible constraint returns Nothing" $ do
      let rdIsZero  = ConstraintDef "rd-zero"    [] "" [] (\s -> symRd s .== 0)
          rdNonZero = ConstraintDef "rd-nonzero" [] "" [] (\s -> symRd s ./= 0)
          cs = addConstraint rdIsZero (addConstraint rdNonZero emptyConstraintSet)
      result <- solve cs
      result @?= Nothing
  , testCase "single constraint rd != 0 gives valid params" $ do
      let rdNZ = ConstraintDef "rd-nonzero" [] "" [] (\s -> symRd s ./= 0)
          cs   = addConstraint rdNZ emptyConstraintSet
      result <- solve cs
      case result of
        Nothing -> assertFailure "expected a solution"
        Just p  -> (ipRd p /= 0) @?= True
  ]
