module Test.Core.Encode (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Core.Types

tests :: TestTree
tests = testGroup "Core.Types"
  [ testCase "x0 is register 0" $
      unReg x0 @?= 0
  , testCase "AqRl has 4 constructors" $
      length [minBound..maxBound :: AqRl] @?= 4
  , testCase "RoundingMode has 6 constructors" $
      length [minBound..maxBound :: RoundingMode] @?= 6
  , testCase "PrivilegeLevel ordering: User < Machine" $
      (User < Machine) @?= True
  ]
