module Test.Core.Encode (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Core.Types
import Core.Instruction

tests :: TestTree
tests = testGroup "Core"
  [ typeTests
  , instrTests
  ]

typeTests :: TestTree
typeTests = testGroup "Core.Types"
  [ testCase "x0 is register 0" $
      unReg x0 @?= 0
  , testCase "AqRl has 4 constructors" $
      length [minBound..maxBound :: AqRl] @?= 4
  , testCase "RoundingMode has 6 constructors" $
      length [minBound..maxBound :: RoundingMode] @?= 6
  , testCase "PrivilegeLevel ordering: User < Machine" $
      (User < Machine) @?= True
  ]

instrTests :: TestTree
instrTests = testGroup "Core.Instruction"
  [ testCase "ADD is RV64I extension" $
      instrExtension (ADD x1 x2 x3) @?= RV64I
  , testCase "MUL is RV64M extension" $
      instrExtension (MUL x1 x2 x3) @?= RV64M
  , testCase "MRET is Privileged extension" $
      instrExtension MRET @?= RVPriv
  , testCase "InstrFormat of ADD is RFormat" $
      instrFormat (ADD x1 x2 x3) @?= RFormat
  , testCase "InstrFormat of ADDI is IFormat" $
      instrFormat (ADDI x1 x2 (Imm12 0)) @?= IFormat
  , testCase "InstrFormat of BEQ is BFormat" $
      instrFormat (BEQ x1 x2 (Imm13 0)) @?= BFormat
  ]
