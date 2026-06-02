module Test.Coverage.Classify (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Coverage.Types  (allOpcodeBins, CoverageBin(..))
import Data.Text       (pack)

tests :: TestTree
tests = testGroup "Coverage.Classify (auto-derive)"
  [ testCase "allOpcodeBins contains OpcodeBin ADD" $
      OpcodeBin (pack "ADD") `elem` allOpcodeBins @?= True

  , testCase "allOpcodeBins contains OpcodeBin LR_D" $
      OpcodeBin (pack "LR_D") `elem` allOpcodeBins @?= True

  , testCase "allOpcodeBins contains OpcodeBin C_ADDI4SPN" $
      OpcodeBin (pack "C_ADDI4SPN") `elem` allOpcodeBins @?= True

  , testCase "allOpcodeBins is non-empty" $
      null allOpcodeBins @?= False

  , testCase "allOpcodeBins length is at least 150" $
      length allOpcodeBins >= 150 @?= True
  ]
