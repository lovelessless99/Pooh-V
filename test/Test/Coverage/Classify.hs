module Test.Coverage.Classify (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Coverage.Types    (allOpcodeBins, CoverageBin(..), SequencePattern(..), ValueCategory(..))
import Coverage.Detector (allDetectors, pdPattern, pdDetect)
import Coverage.Classify (classifySequence)
import Core.Instruction  (Instruction(..))
import Core.Types        (x0, x1, x2, AqRl(..), Imm12(..), Imm13(..))
import Data.List         (nub)
import Data.Text         (pack)

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

  , testCase "allDetectors covers all SequencePattern values" $
      let covered = map pdPattern allDetectors
          allPats = [minBound .. maxBound] :: [SequencePattern]
      in  all (`elem` covered) allPats @?= True

  , testCase "lrscPair detector fires on LR_D + SC_D sequence" $
      let instrs = [ LR_D x1 x2 AqRlAcqRel
                   , SC_D x1 x2 x1 AqRlAcqRel
                   ]
          det = head [ d | d <- allDetectors, pdPattern d == LrscPair ]
      in  pdDetect det instrs @?= True

  , testCase "backwardBranch detector fires on negative offset" $
      let instrs = [ BEQ x1 x2 (Imm13 (-4)) ]
          det = head [ d | d <- allDetectors, pdPattern d == BackwardBranch ]
      in  pdDetect det instrs @?= True

  , testCase "classifySequence: ADD x1 x2 x0 → OpcodeBin ADD" $
      OpcodeBin (pack "ADD") `elem` classifySequence [ADD x1 x2 x0] @?= True

  , testCase "classifySequence: ADDI imm=0 → ValueBin Zero" $
      ValueBin Zero `elem` classifySequence [ADDI x1 x2 (Imm12 0)] @?= True

  , testCase "classifySequence: ADDI imm=(-1) → ValueBin AllOnes" $
      ValueBin AllOnes `elem` classifySequence [ADDI x1 x2 (Imm12 (-1))] @?= True

  , testCase "classifySequence: LR_D + SC_D → PatternBin LrscPair" $
      PatternBin LrscPair `elem`
        classifySequence [LR_D x1 x2 AqRlAcqRel, SC_D x1 x2 x1 AqRlAcqRel] @?= True

  , testCase "classifySequence: BEQ with negative offset → PatternBin BackwardBranch" $
      PatternBin BackwardBranch `elem`
        classifySequence [BEQ x1 x2 (Imm13 (-4))] @?= True

  , testCase "classifySequence: empty list → empty result" $
      classifySequence [] @?= []

  , testCase "classifySequence: no duplicate bins" $
      let bins = classifySequence [ADD x1 x2 x0, ADD x1 x2 x0]
      in  length bins == length (nub bins) @?= True
  ]
