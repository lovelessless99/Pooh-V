module Test.Coverage.Bins (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Coverage.Types
import Core.Types       (PrivilegeLevel(..))

tests :: TestTree
tests = testGroup "Coverage bins"
  [ testCase "PatternBin LrscPair has Show instance" $
      show (PatternBin LrscPair) @?= "PatternBin LrscPair"

  , testCase "ValueBin Zero has Show instance" $
      show (ValueBin Zero) @?= "ValueBin Zero"

  , testCase "OpcodeModeBin has Show instance" $
      show (OpcodeModeBin "ADD" Machine) @?= "OpcodeModeBin \"ADD\" Machine"

  , testCase "allCoverageBins includes PatternBin LrscPair" $
      PatternBin LrscPair `elem` allCoverageBins @?= True

  , testCase "allCoverageBins includes all ValueCategory variants" $
      all (\vc -> ValueBin vc `elem` allCoverageBins)
          [minBound..maxBound :: ValueCategory]
      @?= True

  , testCase "allCoverageBins includes OpcodeModeBin for ADDI Machine" $
      OpcodeModeBin "ADDI" Machine `elem` allCoverageBins @?= True

  , testCase "allOpcodeBins still contains RV64I mnemonics" $
      OpcodeBin "ADD" `elem` allOpcodeBins @?= True

  , testCase "allOpcodeBins contains RV64A mnemonics" $
      OpcodeBin "LR_W" `elem` allOpcodeBins @?= True

  , testCase "allOpcodeBins contains RV64F mnemonics" $
      OpcodeBin "FADD_S" `elem` allOpcodeBins @?= True
  ]
