module Test.Core.Atomic (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Data.Bits    (shiftR, (.&.))
import Core.Types
import Core.Instruction
import Core.Encode  (encode)
import Core.Decode  (decode)

tests :: TestTree
tests = testGroup "RV64A"
  [ testCase "LR_W encode opcode is 0x2F" $ do
      let w = encode (LR_W x1 x2 AqRlNone)
      (w .&. 0x7F) @?= 0x2F

  , testCase "LR_W funct3=010 (word)" $ do
      let w = encode (LR_W x1 x2 AqRlNone)
      ((w `shiftR` 12) .&. 0x7) @?= 0x2

  , testCase "LR_D funct3=011 (double)" $ do
      let w = encode (LR_D x1 x2 AqRlAcquire)
      ((w `shiftR` 12) .&. 0x7) @?= 0x3

  , testCase "LR_W aq=0 rl=0 for AqRlNone" $ do
      let w = encode (LR_W x1 x2 AqRlNone)
      ((w `shiftR` 25) .&. 0x3) @?= 0x0

  , testCase "LR_W aq=1 rl=1 for AqRlAcqRel" $ do
      let w = encode (LR_W x1 x2 AqRlAcqRel)
      ((w `shiftR` 25) .&. 0x3) @?= 0x3

  , testCase "SC_W funct5=00011" $ do
      let w = encode (SC_W x1 x2 x3 AqRlNone)
      ((w `shiftR` 27) .&. 0x1F) @?= 0x03

  , testCase "AMOADD_W funct5=00000" $ do
      let w = encode (AMOADD_W x1 x2 x3 AqRlNone)
      ((w `shiftR` 27) .&. 0x1F) @?= 0x00

  , testCase "AMOSWAP_W funct5=00001" $ do
      let w = encode (AMOSWAP_W x1 x2 x3 AqRlNone)
      ((w `shiftR` 27) .&. 0x1F) @?= 0x01

  , testCase "AMOADD_W encode/decode round-trip" $ do
      let instr = AMOADD_W x5 x6 x7 AqRlRelease
      decode (encode instr) @?= Right instr

  , testCase "AMOSWAP_D encode/decode round-trip" $ do
      let instr = AMOSWAP_D x1 x2 x3 AqRlAcqRel
      decode (encode instr) @?= Right instr
  ]
