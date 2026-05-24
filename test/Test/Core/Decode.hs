module Test.Core.Decode (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog
import Hedgehog
import qualified Hedgehog.Gen   as Gen
import qualified Hedgehog.Range as Range
import Core.Types
import Core.Instruction
import Core.Encode
import Core.Decode

tests :: TestTree
tests = testGroup "Core.Decode"
  [ testCase "decode known ADD" $
      decode 0x003100B3 @?= Right (ADD (Register 1) (Register 2) (Register 3))
  , testCase "decode unknown opcode returns Left" $
      case decode 0xFFFFFFFF of
        Left _ -> return ()
        Right _ -> assertFailure "expected DecodeError"
  , testProperty "encode/decode roundtrip for sample instructions" $
      property $ do
        instr <- forAll genSampleInstruction
        decode (encode instr) === Right instr
  ]

genSampleInstruction :: Gen Instruction
genSampleInstruction = Gen.choice
  [ ADD  <$> genReg <*> genReg <*> genReg
  , SUB  <$> genReg <*> genReg <*> genReg
  , ADDI <$> genReg <*> genReg <*> genImm12
  , LUI  <$> genReg <*> genImm20
  , LW   <$> genReg <*> genReg <*> genImm12
  , SW   <$> genReg <*> genReg <*> genImm12
  , BEQ  <$> genReg <*> genReg <*> genImm13Even
  , JAL  <$> genReg <*> genImm21Even
  , MUL  <$> genReg <*> genReg <*> genReg
  , pure ECALL
  , pure MRET
  ]
  where
    genReg       = Register  <$> Gen.word8 (Range.linear 0 31)
    genImm12     = Imm12     <$> Gen.int16 (Range.linearFrom 0 (-2048) 2047)
    genImm20     = Imm20     <$> Gen.int32 (Range.linearFrom 0 0 0xFFFFF)
    genImm13Even = Imm13 . (\x -> x - x `mod` 2)
                         <$> Gen.int16 (Range.linearFrom 0 (-4096) 4094)
    genImm21Even = Imm21 . (\x -> x - x `mod` 2)
                         <$> Gen.int32 (Range.linearFrom 0 (-1048576) 1048574)
