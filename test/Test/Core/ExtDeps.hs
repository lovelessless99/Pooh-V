module Test.Core.ExtDeps (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Core.Instruction (Extension(..))
import Core.ExtDeps
import qualified Data.Set as Set

tests :: TestTree
tests = testGroup "Extension dependencies"
  [ testCase "RV64I has no deps" $
      directDeps RV64I @?= []

  , testCase "RV64D depends on RV64F" $
      RV64F `elem` directDeps RV64D @?= True

  , testCase "allDepsOf {RV64D} includes RV64F and RV64I" $ do
      let deps = allDepsOf (Set.singleton RV64D)
      Set.member RV64F deps @?= True
      Set.member RV64I deps @?= True

  , testCase "allDepsOf {RV64A} includes RV64I" $ do
      let deps = allDepsOf (Set.singleton RV64A)
      Set.member RV64I deps @?= True

  , testCase "allDepsOf is idempotent" $ do
      let base  = Set.fromList [RV64D, RV64A]
          once  = allDepsOf base
          twice = allDepsOf once
      once @?= twice

  , testCase "resolveExtensions {RV64D} includes I, F, D" $ do
      let resolved = resolveExtensions (Set.singleton RV64D)
      Set.member RV64I resolved @?= True
      Set.member RV64F resolved @?= True
      Set.member RV64D resolved @?= True
  ]
