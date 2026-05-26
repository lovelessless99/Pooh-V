module Test.ELF.FlatBinary (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Data.ByteString.Lazy as BL
import ELF.FlatBinary
import Core.Types
import Core.Instruction

tests :: TestTree
tests = testGroup "ELF.FlatBinary"
  [ testCase "ELF magic bytes are correct" $ do
      bs <- generateElf emptyTestProgram "/dev/null"
      let magic = BL.unpack (BL.take 4 bs)
      magic @?= [0x7F, 0x45, 0x4C, 0x46]
  , testCase "ELF class is 64-bit (byte 4 = 2)" $ do
      bs <- generateElf emptyTestProgram "/dev/null"
      BL.index bs 4 @?= 2
  , testCase "ELF machine is EM_RISCV (0xF3)" $ do
      bs <- generateElf emptyTestProgram "/dev/null"
      BL.index bs 18 @?= 0xF3
      BL.index bs 19 @?= 0x00
  , testCase "ELF has 2 program headers" $ do
      bs <- generateElf emptyTestProgram "/dev/null"
      BL.index bs 56 @?= 2
  ]

emptyTestProgram :: TestProgram
emptyTestProgram = TestProgram
  { tpStartup     = []
  , tpTrapHandler = []
  , tpTestBody    = [ADDI x1 x0 (Imm12 42)]
  , tpExit        = []
  }
