module Test.Core.Encode (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Core.Types
import Core.Instruction
import Core.Encode
import Core.CSR
import Data.Word (Word32)

tests :: TestTree
tests = testGroup "Core"
  [ typeTests
  , instrTests
  , encodeTests
  , csrTests
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

encodeTests :: TestTree
encodeTests = testGroup "Core.Encode"
  [ testCase "ADD x1,x2,x3 = 0x003100B3" $
      encode (ADD (Register 1) (Register 2) (Register 3)) @?= 0x003100B3
  , testCase "ADDI x1,x0,1 = 0x00100093" $
      encode (ADDI (Register 1) (Register 0) (Imm12 1)) @?= 0x00100093
  , testCase "LUI x1,1 = 0x000010B7" $
      encode (LUI (Register 1) (Imm20 1)) @?= 0x000010B7
  , testCase "JAL x0,0 = 0x0000006F" $
      encode (JAL (Register 0) (Imm21 0)) @?= 0x0000006F
  , testCase "BEQ x1,x2,0 = 0x00208063" $
      encode (BEQ (Register 1) (Register 2) (Imm13 0)) @?= 0x00208063
  , testCase "SW x2,0(x1) = 0x0020A023" $
      encode (SW (Register 2) (Register 1) (Imm12 0)) @?= 0x0020A023
  , testCase "MUL x1,x2,x3 = 0x023100B3" $
      encode (MUL (Register 1) (Register 2) (Register 3)) @?= 0x023100B3
  , testCase "ECALL = 0x00000073" $
      encode ECALL @?= 0x00000073
  , testCase "MRET = 0x30200073" $
      encode MRET @?= 0x30200073
  , testCase "CSRRW x1,mstatus,x0 = 0x300010F3" $
      encode (CSRRW (Register 1) (CSRAddr 0x300) (Register 0)) @?= 0x300010F3
  ]

csrTests :: TestTree
csrTests = testGroup "Core.CSR"
  [ testCase "mstatus address is 0x300" $
      csrAddr Mstatus @?= CSRAddr 0x300
  , testCase "all CSR addresses are unique" $
      let addrs = map csrAddr [minBound..maxBound]
      in  length addrs @?= length (nub addrs)
  , testCase "Mstatus requires Machine privilege to write" $
      writePriv (csrAccessRules Mstatus) @?= Machine
  , testCase "Cycle is read-only" $
      readOnly (csrAccessRules Cycle) @?= True
  ]
  where nub [] = []; nub (x:xs) = x : nub (filter (/=x) xs)
