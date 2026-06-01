module Test.Core.FloatInstr (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Data.Bits    (shiftR, (.&.))
import Core.Types
import Core.Instruction
import Core.Encode  (encode)
import Core.Decode  (decode)

tests :: TestTree
tests = testGroup "RV64F+D"
  [ testCase "FLW opcode=0x07 funct3=010" $ do
      let w = encode (FLW fa0 x1 (Imm12 0))
      (w .&. 0x7F) @?= 0x07
      ((w `shiftR` 12) .&. 0x7) @?= 0x2

  , testCase "FSW opcode=0x27 funct3=010" $ do
      let w = encode (FSW fa0 x1 (Imm12 0))
      (w .&. 0x7F) @?= 0x27
      ((w `shiftR` 12) .&. 0x7) @?= 0x2

  , testCase "FADD_S funct7=0x00" $ do
      let w = encode (FADD_S fa0 fa1 fa2 RNE)
      ((w `shiftR` 25) .&. 0x7F) @?= 0x00

  , testCase "FADD_D funct7=0x01" $ do
      let w = encode (FADD_D fa0 fa1 fa2 RNE)
      ((w `shiftR` 25) .&. 0x7F) @?= 0x01

  , testCase "FMADD_S opcode=0x43 funct2=00" $ do
      let w = encode (FMADD_S fa0 fa1 fa2 fa3 RNE)
      (w .&. 0x7F) @?= 0x43
      ((w `shiftR` 25) .&. 0x3) @?= 0x0

  , testCase "FMADD_D funct2=01" $ do
      let w = encode (FMADD_D fa0 fa1 fa2 fa3 RNE)
      ((w `shiftR` 25) .&. 0x3) @?= 0x1

  , testCase "FADD_S encode/decode round-trip" $ do
      let instr = FADD_S fa1 fa2 fa3 RTZ
      decode (encode instr) @?= Right instr

  , testCase "FLW encode/decode round-trip" $ do
      let instr = FLW fa0 x5 (Imm12 16)
      decode (encode instr) @?= Right instr

  , testCase "FCVT_W_S funct7=0x60 rs2-field=0" $ do
      let w = encode (FCVT_W_S x1 fa0 RNE)
      ((w `shiftR` 25) .&. 0x7F) @?= 0x60
      ((w `shiftR` 20) .&. 0x1F) @?= 0x00

  , testCase "FMV_X_W funct7=0x70 funct3=0x0" $ do
      let w = encode (FMV_X_W x1 fa0)
      ((w `shiftR` 25) .&. 0x7F) @?= 0x70
      ((w `shiftR` 12) .&. 0x7)  @?= 0x00
  ]
