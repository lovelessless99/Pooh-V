module Test.Constraint.Solver (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Core.Types ()
import Constraint.Types
import Constraint.Solver
import Constraint.Library      (rdNotZero, rs1NotZero, rs2NotZero)
import Constraint.Combinators  (mergeConstraints)
import Data.SBV                ((.==), (./=))
import System.IO.Error         (tryIOError)
import System.Process          (readProcessWithExitCode)

z3Available :: IO Bool
z3Available = do
  r <- tryIOError (readProcessWithExitCode "z3" ["--version"] "")
  return $ case r of
    Left  _ -> False
    Right _ -> True

requireZ3 :: Assertion -> Assertion
requireZ3 action = do
  avail <- z3Available
  if avail then action else return ()

tests :: TestTree
tests = testGroup "Constraint.Solver"
  [ testCase "empty constraint set is satisfiable" $ requireZ3 $ do
      result <- solve emptyConstraintSet
      case result of
        Just _  -> return ()
        Nothing -> assertFailure "expected a solution"
  , testCase "infeasible constraint returns Nothing" $ requireZ3 $ do
      let rdIsZero  = ConstraintDef "rd-zero"    [] "" [] (\s -> symRd s .== 0)
          rdNonZero = ConstraintDef "rd-nonzero" [] "" [] (\s -> symRd s ./= 0)
          cs = addConstraint rdIsZero (addConstraint rdNonZero emptyConstraintSet)
      result <- solve cs
      result @?= Nothing
  , testCase "single constraint rd != 0 gives valid params" $ requireZ3 $ do
      let rdNZ = ConstraintDef "rd-nonzero" [] "" [] (\s -> symRd s ./= 0)
          cs   = addConstraint rdNZ emptyConstraintSet
      result <- solve cs
      case result of
        Nothing -> assertFailure "expected a solution"
        Just p  -> (ipRd p /= 0) @?= True
  , testCase "rdNotZero AND rs1NotZero gives rd/=0, rs1/=0" $ requireZ3 $ do
      let cs = addConstraint rdNotZero (addConstraint rs1NotZero emptyConstraintSet)
      result <- solve cs
      case result of
        Nothing -> assertFailure "expected solution"
        Just p  -> do
          (ipRd p /= 0)  @?= True
          (ipRs1 p /= 0) @?= True
  , testCase "mergeConstraints combines both sets" $ requireZ3 $ do
      let cs1 = addConstraint rdNotZero  emptyConstraintSet
          cs2 = addConstraint rs2NotZero emptyConstraintSet
          cs  = mergeConstraints cs1 cs2
      result <- solve cs
      case result of
        Nothing -> assertFailure "expected solution"
        Just p  -> do
          (ipRd p  /= 0) @?= True
          (ipRs2 p /= 0) @?= True
  ]
