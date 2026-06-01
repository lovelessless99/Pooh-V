module Test.CoSim.Shrink (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Core.Types
import Core.Instruction
import CoSim.Shrink

tests :: TestTree
tests = testGroup "CoSim.Shrink"
  [ testCase "shrink empty sequence stays empty" $ do
      result <- shrinkSequence (\_ -> return True) []
      result @?= []

  , testCase "shrink removes instructions that dont affect predicate" $ do
      let seq_ = [ ADD x1 x2 x3, ADDI x1 x2 (Imm12 0), SUB x3 x4 x5, ADDI x2 x3 (Imm12 1) ]
          pred_ instrs = return $ any isAddi instrs
          isAddi (ADDI{}) = True; isAddi _ = False
      result <- shrinkSequence pred_ seq_
      any isAddi result @?= True
      length result < length seq_ @?= True

  , testCase "shrink stops when no instruction can be removed" $ do
      let seq_ = [ADDI x1 x2 (Imm12 5)]
          pred_ instrs = return $ length instrs == 1
      result <- shrinkSequence pred_ seq_
      result @?= [ADDI x1 x2 (Imm12 5)]

  , testCase "shrink returns empty when predicate satisfied by empty" $ do
      let seq_ = [ADD x1 x2 x3, SUB x4 x5 x6]
          pred_ _ = return True
      result <- shrinkSequence pred_ seq_
      result @?= []
  ]
