module Core.Decode
  ( decode
  , DecodeError(..)
  ) where

import Core.Types
import Core.Instruction
import Data.Bits  (shiftL, shiftR, (.|.), (.&.), testBit)
import Data.Word  (Word32)
import Data.Int   (Int16, Int32)

data DecodeError
  = UnknownOpcode     Word32
  | UnknownFunct3     Word32 Word32
  | UnknownFunct7     Word32 Word32 Word32
  | ReservedEncoding  Word32
  deriving (Show, Eq)

field :: Word32 -> Int -> Int -> Word32
field w hi lo = (w `shiftR` lo) .&. ((1 `shiftL` (hi - lo + 1)) - 1)

opcode, rd', funct3', rs1', rs2', funct7' :: Word32 -> Word32
opcode  w = field w  6  0
rd'     w = field w 11  7
funct3' w = field w 14 12
rs1'    w = field w 19 15
rs2'    w = field w 24 20
funct7' w = field w 31 25

signExt12 :: Word32 -> Int16
signExt12 w =
  let v = fromIntegral (w .&. 0xFFF) :: Int16
  in  if testBit v 11 then v - 0x1000 else v

signExt13 :: Word32 -> Int16
signExt13 w =
  let b12   = field w 31 31
      b11   = field w  7  7
      b10_5 = field w 30 25
      b4_1  = field w 11  8
      raw   = fromIntegral
                ((b12 `shiftL` 12) .|. (b11 `shiftL` 11)
                 .|. (b10_5 `shiftL` 5) .|. (b4_1 `shiftL` 1)) :: Int16
  in  if testBit raw 12 then raw - 0x2000 else raw

-- U-type immediate: unsigned 20-bit value, stored as non-negative Int32.
-- Not truly sign-extended — Imm20 values are always in [0, 0xFFFFF].
extractImm20 :: Word32 -> Int32
extractImm20 w = fromIntegral (field w 31 12)

signExt21 :: Word32 -> Int32
signExt21 w =
  let b20    = field w 31 31
      b19_12 = field w 19 12
      b11    = field w 20 20
      b10_1  = field w 30 21
      raw    = fromIntegral
                 ((b20 `shiftL` 20) .|. (b19_12 `shiftL` 12) .|.
                  (b11 `shiftL` 11) .|. (b10_1  `shiftL` 1)) :: Int32
  in  if testBit raw 20 then raw - 0x200000 else raw

mkReg :: Word32 -> Register
mkReg = Register . fromIntegral

mkCSR :: Word32 -> CSRAddr
mkCSR = CSRAddr . fromIntegral

mkUImm5 :: Word32 -> UImm5
mkUImm5 = UImm5 . fromIntegral

mkUImm6 :: Word32 -> UImm6
mkUImm6 = UImm6 . fromIntegral

decode :: Word32 -> Either DecodeError Instruction
decode w = case opcode w of
  0x33 -> decodeR33 w
  0x3B -> decodeR3B w
  0x13 -> decodeI13 w
  0x1B -> decodeI1B w
  0x03 -> decodeLoad w
  0x23 -> decodeStore w
  0x63 -> decodeBranch w
  0x37 -> Right $ LUI   (mkReg (rd' w)) (Imm20 (extractImm20 w))
  0x17 -> Right $ AUIPC (mkReg (rd' w)) (Imm20 (extractImm20 w))
  0x6F -> Right $ JAL   (mkReg (rd' w)) (Imm21 (signExt21 w))
  0x67 -> Right $ JALR  (mkReg (rd' w)) (mkReg (rs1' w)) (Imm12 (signExt12 (field w 31 20)))
  0x73 -> decodeSystem w
  0x0F -> decodeFence w
  op   -> Left (UnknownOpcode op)

decodeR33 :: Word32 -> Either DecodeError Instruction
decodeR33 w = case (funct3' w, funct7' w) of
  (0x0, 0x00) -> Right $ ADD  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x0, 0x20) -> Right $ SUB  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x7, 0x00) -> Right $ AND  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x6, 0x00) -> Right $ OR   (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x4, 0x00) -> Right $ XOR  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x1, 0x00) -> Right $ SLL  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x5, 0x00) -> Right $ SRL  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x5, 0x20) -> Right $ SRA  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x2, 0x00) -> Right $ SLT  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x3, 0x00) -> Right $ SLTU (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x0, 0x01) -> Right $ MUL    (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x1, 0x01) -> Right $ MULH   (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x2, 0x01) -> Right $ MULHSU (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x3, 0x01) -> Right $ MULHU  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x4, 0x01) -> Right $ DIV    (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x5, 0x01) -> Right $ DIVU   (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x6, 0x01) -> Right $ REM    (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x7, 0x01) -> Right $ REMU   (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (f3, f7)    -> Left (UnknownFunct7 (opcode w) f3 f7)

decodeR3B :: Word32 -> Either DecodeError Instruction
decodeR3B w = case (funct3' w, funct7' w) of
  (0x0, 0x00) -> Right $ ADDW  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x0, 0x20) -> Right $ SUBW  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x1, 0x00) -> Right $ SLLW  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x5, 0x00) -> Right $ SRLW  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x5, 0x20) -> Right $ SRAW  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x0, 0x01) -> Right $ MULW  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x4, 0x01) -> Right $ DIVW  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x5, 0x01) -> Right $ DIVUW (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x6, 0x01) -> Right $ REMW  (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (0x7, 0x01) -> Right $ REMUW (mkReg (rd' w)) (mkReg (rs1' w)) (mkReg (rs2' w))
  (f3, f7)    -> Left (UnknownFunct7 (opcode w) f3 f7)

decodeI13 :: Word32 -> Either DecodeError Instruction
decodeI13 w =
  let imm    = Imm12 (signExt12 (field w 31 20))
      shamt6 = mkUImm6 (field w 25 20)
      funct6 = field w 31 26
  in case funct3' w of
    0x0 -> Right $ ADDI  (mkReg (rd' w)) (mkReg (rs1' w)) imm
    0x7 -> Right $ ANDI  (mkReg (rd' w)) (mkReg (rs1' w)) imm
    0x6 -> Right $ ORI   (mkReg (rd' w)) (mkReg (rs1' w)) imm
    0x4 -> Right $ XORI  (mkReg (rd' w)) (mkReg (rs1' w)) imm
    0x2 -> Right $ SLTI  (mkReg (rd' w)) (mkReg (rs1' w)) imm
    0x3 -> Right $ SLTIU (mkReg (rd' w)) (mkReg (rs1' w)) imm
    0x1 -> case funct6 of
      0x00 -> Right $ SLLI (mkReg (rd' w)) (mkReg (rs1' w)) shamt6
      _    -> Left (UnknownFunct7 (opcode w) (funct3' w) funct6)
    0x5 -> case funct6 of
      0x00 -> Right $ SRLI (mkReg (rd' w)) (mkReg (rs1' w)) shamt6
      0x10 -> Right $ SRAI (mkReg (rd' w)) (mkReg (rs1' w)) shamt6
      _    -> Left (UnknownFunct7 (opcode w) (funct3' w) funct6)
    f3 -> Left (UnknownFunct3 (opcode w) f3)

decodeI1B :: Word32 -> Either DecodeError Instruction
decodeI1B w =
  let shamt5  = mkUImm5 (field w 24 20)
      funct7v = funct7' w
  in case funct3' w of
    0x0 -> Right $ ADDIW (mkReg (rd' w)) (mkReg (rs1' w)) (Imm12 (signExt12 (field w 31 20)))
    0x1 -> case funct7v of
      0x00 -> Right $ SLLIW (mkReg (rd' w)) (mkReg (rs1' w)) shamt5
      _    -> Left (UnknownFunct7 (opcode w) (funct3' w) funct7v)
    0x5 -> case funct7v of
      0x00 -> Right $ SRLIW (mkReg (rd' w)) (mkReg (rs1' w)) shamt5
      0x20 -> Right $ SRAIW (mkReg (rd' w)) (mkReg (rs1' w)) shamt5
      _    -> Left (UnknownFunct7 (opcode w) (funct3' w) funct7v)
    f3 -> Left (UnknownFunct3 (opcode w) f3)

decodeLoad :: Word32 -> Either DecodeError Instruction
decodeLoad w =
  let imm = Imm12 (signExt12 (field w 31 20))
  in case funct3' w of
    0x0 -> Right $ LB  (mkReg (rd' w)) (mkReg (rs1' w)) imm
    0x1 -> Right $ LH  (mkReg (rd' w)) (mkReg (rs1' w)) imm
    0x2 -> Right $ LW  (mkReg (rd' w)) (mkReg (rs1' w)) imm
    0x3 -> Right $ LD  (mkReg (rd' w)) (mkReg (rs1' w)) imm
    0x4 -> Right $ LBU (mkReg (rd' w)) (mkReg (rs1' w)) imm
    0x5 -> Right $ LHU (mkReg (rd' w)) (mkReg (rs1' w)) imm
    0x6 -> Right $ LWU (mkReg (rd' w)) (mkReg (rs1' w)) imm
    f3  -> Left (UnknownFunct3 (opcode w) f3)

decodeStore :: Word32 -> Either DecodeError Instruction
decodeStore w =
  let imm = Imm12 (signExt12 ((field w 31 25 `shiftL` 5) .|. field w 11 7))
  in case funct3' w of
    0x0 -> Right $ SB (mkReg (rs2' w)) (mkReg (rs1' w)) imm
    0x1 -> Right $ SH (mkReg (rs2' w)) (mkReg (rs1' w)) imm
    0x2 -> Right $ SW (mkReg (rs2' w)) (mkReg (rs1' w)) imm
    0x3 -> Right $ SD (mkReg (rs2' w)) (mkReg (rs1' w)) imm
    f3  -> Left (UnknownFunct3 (opcode w) f3)

decodeBranch :: Word32 -> Either DecodeError Instruction
decodeBranch w =
  let imm = Imm13 (signExt13 w)
  in case funct3' w of
    0x0 -> Right $ BEQ  (mkReg (rs1' w)) (mkReg (rs2' w)) imm
    0x1 -> Right $ BNE  (mkReg (rs1' w)) (mkReg (rs2' w)) imm
    0x4 -> Right $ BLT  (mkReg (rs1' w)) (mkReg (rs2' w)) imm
    0x5 -> Right $ BGE  (mkReg (rs1' w)) (mkReg (rs2' w)) imm
    0x6 -> Right $ BLTU (mkReg (rs1' w)) (mkReg (rs2' w)) imm
    0x7 -> Right $ BGEU (mkReg (rs1' w)) (mkReg (rs2' w)) imm
    f3  -> Left (UnknownFunct3 (opcode w) f3)

decodeSystem :: Word32 -> Either DecodeError Instruction
decodeSystem w = case (funct3' w, field w 31 20) of
  (0x0, 0x000) -> Right ECALL
  (0x0, 0x001) -> Right EBREAK
  (0x0, 0x302) -> Right MRET
  (0x0, 0x102) -> Right SRET
  (0x0, 0x105) -> Right WFI
  (0x0, _)     ->
    let f7 = funct7' w
    in if f7 == 0x09
       then Right $ SFENCE_VMA (mkReg (rs1' w)) (mkReg (rs2' w))
       else Left (ReservedEncoding w)
  (0x1, _) -> Right $ CSRRW  (mkReg (rd' w)) (mkCSR (field w 31 20)) (mkReg (rs1' w))
  (0x2, _) -> Right $ CSRRS  (mkReg (rd' w)) (mkCSR (field w 31 20)) (mkReg (rs1' w))
  (0x3, _) -> Right $ CSRRC  (mkReg (rd' w)) (mkCSR (field w 31 20)) (mkReg (rs1' w))
  (0x5, _) -> Right $ CSRRWI (mkReg (rd' w)) (mkCSR (field w 31 20)) (mkUImm5 (rs1' w))
  (0x6, _) -> Right $ CSRRSI (mkReg (rd' w)) (mkCSR (field w 31 20)) (mkUImm5 (rs1' w))
  (0x7, _) -> Right $ CSRRCI (mkReg (rd' w)) (mkCSR (field w 31 20)) (mkUImm5 (rs1' w))
  (f3, _)  -> Left (UnknownFunct3 (opcode w) f3)

decodeFence :: Word32 -> Either DecodeError Instruction
decodeFence w = case funct3' w of
  0x0 ->
    let decodeFm bits = FenceMode
          { fenceI = testBit (bits :: Word32) 3
          , fenceO = testBit (bits :: Word32) 2
          , fenceR = testBit (bits :: Word32) 1
          , fenceW = testBit (bits :: Word32) 0
          }
        pre = decodeFm (field w 27 24)
        suc = decodeFm (field w 23 20)
    in Right $ FENCE pre suc
  0x1 -> Right FENCE_I
  f3  -> Left (UnknownFunct3 (opcode w) f3)
