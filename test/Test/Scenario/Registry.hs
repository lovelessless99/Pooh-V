module Test.Scenario.Registry (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Scenario.Registry
import Scenario.Types
import Core.Instruction (Extension(..))
import Data.Maybe (isNothing)

tests :: TestTree
tests = testGroup "Scenario registry"
  [ testCase "allScenarios is non-empty" $
      null allScenarios @?= False

  , testCase "findByName returns Nothing for unknown name" $
      isNothing (findByName "nonexistent-scenario") @?= True

  , testCase "findByName finds lrsc-timer-interrupt" $
      fmap sName (findByName "lrsc-timer-interrupt") @?= Just "lrsc-timer-interrupt"

  , testCase "findByTag Atomic returns at least one scenario" $
      null (findByTag Atomic) @?= False

  , testCase "lrsc scenario has RV64A in sExtensions" $ do
      let Just spec = findByName "lrsc-timer-interrupt"
      RV64A `elem` sExtensions spec @?= True
  ]
