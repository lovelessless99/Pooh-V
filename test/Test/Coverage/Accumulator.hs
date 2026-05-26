module Test.Coverage.Accumulator (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Control.Concurrent.STM
import qualified Data.Map.Strict as Map
import Coverage.Types
import Coverage.Accumulator
import Coverage.Analysis

tests :: TestTree
tests = testGroup "Coverage"
  [ testCase "new accumulator starts empty" $ do
      acc <- newAccumulator
      m <- atomically (readTVar (covTVar acc))
      Map.null m @?= True
  , testCase "recording bins increments hit counts" $ do
      acc <- newAccumulator
      atomically $ recordCoverage acc [OpcodeBin "ADD", OpcodeBin "ADD", OpcodeBin "SUB"]
      m <- atomically (readTVar (covTVar acc))
      Map.lookup (OpcodeBin "ADD") m @?= Just 2
      Map.lookup (OpcodeBin "SUB") m @?= Just 1
  , testCase "coverage summary reports correct hit count" $ do
      acc <- newAccumulator
      atomically $ recordCoverage acc [OpcodeBin "ADD"]
      snap <- snapshotCoverage acc
      (hitBins snap >= 1) @?= True
  ]
