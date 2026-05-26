module Test.Generator.Random (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog
import Hedgehog
import Core.Instruction
import Generator.Random
import Generator.Types
import Generator.Seed

tests :: TestTree
tests = testGroup "Generator.Random"
  [ testProperty "generated instructions are valid Instruction values" $
      property $ do
        instr <- forAll (genInstruction defaultExtensions)
        -- Just verify it can be shown (forces full evaluation)
        (length (show instr) > 0) === True
  , testCase "generateSequence returns sequence in config length range" $ do
      let cfg  = defaultConfig
      seed <- newRandomSeed
      let cfg' = cfg { gcSeed = seed }
      seq_ <- generateSequence cfg'
      let l = length seq_
      (l >= gcMinLength cfg && l <= gcMaxLength cfg) @?= True
  , testCase "same seed gives same sequence" $ do
      let cfg = defaultConfig { gcSeed = seedFromWord64 12345 }
      seq1 <- generateSequence cfg
      seq2 <- generateSequence cfg
      seq1 @?= seq2
  ]

defaultExtensions :: [Extension]
defaultExtensions = [RV64I, RV64M]
