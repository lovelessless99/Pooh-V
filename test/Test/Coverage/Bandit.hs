module Test.Coverage.Bandit (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Coverage.Bandit
import Coverage.Types  (CoverageBin(..), allCoverageBins)
import qualified Data.Set        as Set
import qualified Data.Map.Strict as Map
import Data.Text       (pack)

tests :: TestTree
tests = testGroup "Coverage.Bandit"
  [ testCase "initBandit creates Beta(1,1) for every bin" $ do
      let bs     = initBandit allCoverageBins
          params = bsParams bs
      Map.size params @?= length allCoverageBins
      let allUniform = all (\(BetaParams a b) -> a == 1.0 && b == 1.0)
                           (Map.elems params)
      allUniform @?= True

  , testCase "updateBandit increments alpha for hit bins" $ do
      let bin = OpcodeBin (pack "ADD")
          bs0 = initBandit [bin]
          bs1 = updateBandit bs0 [bin]
          BetaParams a _ = bsParams bs1 Map.! bin
      a @?= 2.0

  , testCase "updateBandit increments beta for miss bins" $ do
      let bin1 = OpcodeBin (pack "ADD")
          bin2 = OpcodeBin (pack "SUB")
          bs0  = initBandit [bin1, bin2]
          bs1  = updateBandit bs0 [bin1]
          BetaParams _ b = bsParams bs1 Map.! bin2
      b @?= 2.0

  , testCase "markInfeasible adds bin to bsInfeasible set" $ do
      let bin = OpcodeBin (pack "MRET")
          bs0 = initBandit [bin]
          bs1 = markInfeasible bs0 bin
      Set.member bin (bsInfeasible bs1) @?= True

  , testCase "sampleTarget never returns infeasible bin" $ do
      let bins = [OpcodeBin (pack "ADD"), OpcodeBin (pack "MRET")]
          bs0  = initBandit bins
          bs1  = markInfeasible bs0 (OpcodeBin (pack "MRET"))
      result <- sampleTarget bs1
      result @?= OpcodeBin (pack "ADD")

  , testCase "sampleTarget with single eligible bin returns that bin" $ do
      let bin = OpcodeBin (pack "ADDI")
          bs  = initBandit [bin]
      result <- sampleTarget bs
      result @?= bin
  ]
