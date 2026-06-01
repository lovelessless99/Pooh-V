module Test.Core.Compressed (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Data.Bits    (shiftR, (.&.))
import Core.Types
import Core.Instruction
import Core.Encode  (encode16)
import Core.Decode  (decode16)

tests :: TestTree
tests = testGroup "RV64C"
  [ testCase "C_ADDI quadrant=01" $ do
      let w = encode16 (C_ADDI x1 (Imm6 1))
      (w .&. 0x3) @?= 0x1

  , testCase "C_ADDI funct3=000" $ do
      let w = encode16 (C_ADDI x1 (Imm6 1))
      ((w `shiftR` 13) .&. 0x7) @?= 0x0

  , testCase "C_LW quadrant=00 funct3=010" $ do
      let w = encode16 (C_LW x8 x9 (UImm7 0))
      (w .&. 0x3) @?= 0x0
      ((w `shiftR` 13) .&. 0x7) @?= 0x2

  , testCase "C_J quadrant=01 funct3=101" $ do
      let w = encode16 (C_J (Imm12 0))
      (w .&. 0x3) @?= 0x1
      ((w `shiftR` 13) .&. 0x7) @?= 0x5

  , testCase "C_MV quadrant=10 funct4 high=1000" $ do
      let w = encode16 (C_MV x1 x2)
      (w .&. 0x3) @?= 0x2
      ((w `shiftR` 12) .&. 0xF) @?= 0x8

  , testCase "C_ADDI encode/decode round-trip" $ do
      let instr = C_ADDI x5 (Imm6 (-3))
      decode16 (encode16 instr) @?= Right instr

  , testCase "C_LD encode/decode round-trip" $ do
      let instr = C_LD x8 x9 (UImm8 16)
      decode16 (encode16 instr) @?= Right instr

  , testCase "C_BEQZ encode/decode round-trip" $ do
      let instr = C_BEQZ x8 (Imm9 4)
      decode16 (encode16 instr) @?= Right instr
  ]
