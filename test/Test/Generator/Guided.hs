module Test.Generator.Guided (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Coverage.Types    (CoverageBin(..), ValueCategory(..), SequencePattern(..))
import Generator.Guided  (guidedInstruction, guidedSequence)
import Generator.Types   (defaultConfig)
import Coverage.Bandit   (initBandit)
import Coverage.Types    (allCoverageBins)
import Core.Instruction  (Instruction(..))
import Core.Types        (Imm12(..))
import Data.Text         (pack)
import System.IO.Error   (tryIOError)
import System.Process    (readProcessWithExitCode)

z3Available :: IO Bool
z3Available = do
  r <- tryIOError (readProcessWithExitCode "z3" ["--version"] "")
  return $ case r of { Left _ -> False; Right _ -> True }

requireZ3 :: Assertion -> Assertion
requireZ3 action = z3Available >>= \av -> if av then action else return ()

tests :: TestTree
tests = testGroup "Generator.Guided"
  [ testCase "guidedInstruction OpcodeBin ADD returns ADD instruction" $ do
      result <- guidedInstruction (OpcodeBin (pack "ADD")) defaultConfig
      case result of
        Nothing    -> assertFailure "expected an instruction"
        Just (ADD{}) -> return ()
        Just other   -> assertFailure ("expected ADD, got: " <> show other)

  , testCase "guidedInstruction ValueBin Zero returns instr with imm=0" $
      requireZ3 $ do
        result <- guidedInstruction (ValueBin Zero) defaultConfig
        case result of
          Nothing -> assertFailure "expected an instruction"
          Just (ADDI _ _ (Imm12 0)) -> return ()
          Just other -> assertFailure ("unexpected: " <> show other)

  , testCase "guidedInstruction ValueBin AllOnes returns instr with imm=(-1)" $
      requireZ3 $ do
        result <- guidedInstruction (ValueBin AllOnes) defaultConfig
        case result of
          Nothing -> assertFailure "expected an instruction"
          Just (ADDI _ _ (Imm12 (-1))) -> return ()
          Just other -> assertFailure ("unexpected: " <> show other)

  , testCase "guidedSequence returns non-empty sequence" $ do
      let bs = initBandit allCoverageBins
      (seq_, _bins) <- guidedSequence bs defaultConfig 5
      null seq_ @?= False

  , testCase "guidedSequence returns classified bins" $ do
      let bs = initBandit allCoverageBins
      (_seq_, bins) <- guidedSequence bs defaultConfig 5
      null bins @?= False

  , testCase "guidedInstruction LR_D returns Nothing for defaultConfig (no RV64A)" $ do
      result <- guidedInstruction (OpcodeBin (pack "LR_D")) defaultConfig
      result @?= Nothing
  ]
