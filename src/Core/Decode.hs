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
  0x2F -> decodeAMO w
  0x07 -> decodeFPLoad w
  0x27 -> decodeFPStore w
  0x43 -> decodeFMAdd 0x43 w
  0x47 -> decodeFMAdd 0x47 w
  0x4B -> decodeFMAdd 0x4B w
  0x4F -> decodeFMAdd 0x4F w
  0x53 -> decodeFPOp w
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

decodeAqRl :: Word32 -> AqRl
decodeAqRl w = case (field w 26 26, field w 25 25) of
  (0, 0) -> AqRlNone
  (0, 1) -> AqRlRelease
  (1, 0) -> AqRlAcquire
  _      -> AqRlAcqRel

decodeAMO :: Word32 -> Either DecodeError Instruction
decodeAMO w =
  let funct5 = field w 31 27
      funct3 = funct3' w
      rd_    = mkReg (rd' w)
      rs1_   = mkReg (rs1' w)
      rs2_   = mkReg (rs2' w)
      aqrl   = decodeAqRl w
  in case (funct3, funct5) of
    (0x2, 0x02) -> Right $ LR_W  rd_ rs1_ aqrl
    (0x3, 0x02) -> Right $ LR_D  rd_ rs1_ aqrl
    (0x2, 0x03) -> Right $ SC_W  rd_ rs1_ rs2_ aqrl
    (0x3, 0x03) -> Right $ SC_D  rd_ rs1_ rs2_ aqrl
    (0x2, 0x01) -> Right $ AMOSWAP_W rd_ rs1_ rs2_ aqrl
    (0x2, 0x00) -> Right $ AMOADD_W  rd_ rs1_ rs2_ aqrl
    (0x2, 0x04) -> Right $ AMOXOR_W  rd_ rs1_ rs2_ aqrl
    (0x2, 0x0C) -> Right $ AMOAND_W  rd_ rs1_ rs2_ aqrl
    (0x2, 0x08) -> Right $ AMOOR_W   rd_ rs1_ rs2_ aqrl
    (0x2, 0x10) -> Right $ AMOMIN_W  rd_ rs1_ rs2_ aqrl
    (0x2, 0x14) -> Right $ AMOMAX_W  rd_ rs1_ rs2_ aqrl
    (0x2, 0x18) -> Right $ AMOMINU_W rd_ rs1_ rs2_ aqrl
    (0x2, 0x1C) -> Right $ AMOMAXU_W rd_ rs1_ rs2_ aqrl
    (0x3, 0x01) -> Right $ AMOSWAP_D rd_ rs1_ rs2_ aqrl
    (0x3, 0x00) -> Right $ AMOADD_D  rd_ rs1_ rs2_ aqrl
    (0x3, 0x04) -> Right $ AMOXOR_D  rd_ rs1_ rs2_ aqrl
    (0x3, 0x0C) -> Right $ AMOAND_D  rd_ rs1_ rs2_ aqrl
    (0x3, 0x08) -> Right $ AMOOR_D   rd_ rs1_ rs2_ aqrl
    (0x3, 0x10) -> Right $ AMOMIN_D  rd_ rs1_ rs2_ aqrl
    (0x3, 0x14) -> Right $ AMOMAX_D  rd_ rs1_ rs2_ aqrl
    (0x3, 0x18) -> Right $ AMOMINU_D rd_ rs1_ rs2_ aqrl
    (0x3, 0x1C) -> Right $ AMOMAXU_D rd_ rs1_ rs2_ aqrl
    _           -> Left  $ UnknownFunct3 0x2F funct3

mkFP :: Word32 -> FPRegister
mkFP = FPRegister . fromIntegral

decodeRM :: Word32 -> RoundingMode
decodeRM 0 = RNE; decodeRM 1 = RTZ; decodeRM 2 = RDN
decodeRM 3 = RUP; decodeRM 4 = RMM; decodeRM _ = DYN

decodeFPLoad :: Word32 -> Either DecodeError Instruction
decodeFPLoad w = case funct3' w of
  0x2 -> Right $ FLW (mkFP (rd' w)) (mkReg (rs1' w)) (Imm12 (signExt12 (field w 31 20)))
  0x3 -> Right $ FLD (mkFP (rd' w)) (mkReg (rs1' w)) (Imm12 (signExt12 (field w 31 20)))
  f   -> Left  $ UnknownFunct3 0x07 f

decodeFPStore :: Word32 -> Either DecodeError Instruction
decodeFPStore w =
  let imm = Imm12 $ signExt12 $
              ((field w 31 25) `shiftL` 5) .|. (field w 11 7)
  in case funct3' w of
    0x2 -> Right $ FSW (mkFP (rs2' w)) (mkReg (rs1' w)) imm
    0x3 -> Right $ FSD (mkFP (rs2' w)) (mkReg (rs1' w)) imm
    f   -> Left  $ UnknownFunct3 0x27 f

decodeFMAdd :: Word32 -> Word32 -> Either DecodeError Instruction
decodeFMAdd op w =
  let rd_  = mkFP (rd' w); rs1_ = mkFP (rs1' w)
      rs2_ = mkFP (rs2' w); rs3_ = mkFP (field w 31 27)
      rm_  = decodeRM (funct3' w)
      fmt  = field w 26 25
  in case (op, fmt) of
    (0x43, 0) -> Right $ FMADD_S  rd_ rs1_ rs2_ rs3_ rm_
    (0x47, 0) -> Right $ FMSUB_S  rd_ rs1_ rs2_ rs3_ rm_
    (0x4B, 0) -> Right $ FNMSUB_S rd_ rs1_ rs2_ rs3_ rm_
    (0x4F, 0) -> Right $ FNMADD_S rd_ rs1_ rs2_ rs3_ rm_
    (0x43, 1) -> Right $ FMADD_D  rd_ rs1_ rs2_ rs3_ rm_
    (0x47, 1) -> Right $ FMSUB_D  rd_ rs1_ rs2_ rs3_ rm_
    (0x4B, 1) -> Right $ FNMSUB_D rd_ rs1_ rs2_ rs3_ rm_
    (0x4F, 1) -> Right $ FNMADD_D rd_ rs1_ rs2_ rs3_ rm_
    _         -> Left  $ ReservedEncoding w

decodeFPOp :: Word32 -> Either DecodeError Instruction
decodeFPOp w =
  let f7   = funct7' w; f3 = funct3' w
      rd_  = mkFP (rd' w); rdi  = mkReg (rd' w)
      rs1f = mkFP (rs1' w); rs1i = mkReg (rs1' w)
      rs2f = mkFP (rs2' w)
      rs2  = rs2' w
      rm   = decodeRM f3
  in case (f7, f3, rs2) of
    (0x00, _, _)  -> Right $ FADD_S  rd_ rs1f rs2f rm
    (0x04, _, _)  -> Right $ FSUB_S  rd_ rs1f rs2f rm
    (0x08, _, _)  -> Right $ FMUL_S  rd_ rs1f rs2f rm
    (0x0C, _, _)  -> Right $ FDIV_S  rd_ rs1f rs2f rm
    (0x2C, _, 0)  -> Right $ FSQRT_S rd_ rs1f rm
    (0x10, 0, _)  -> Right $ FSGNJ_S  rd_ rs1f rs2f
    (0x10, 1, _)  -> Right $ FSGNJN_S rd_ rs1f rs2f
    (0x10, 2, _)  -> Right $ FSGNJX_S rd_ rs1f rs2f
    (0x14, 0, _)  -> Right $ FMIN_S  rd_ rs1f rs2f
    (0x14, 1, _)  -> Right $ FMAX_S  rd_ rs1f rs2f
    (0x50, 2, _)  -> Right $ FEQ_S   rdi rs1f rs2f
    (0x50, 1, _)  -> Right $ FLT_S   rdi rs1f rs2f
    (0x50, 0, _)  -> Right $ FLE_S   rdi rs1f rs2f
    (0x60, _, 0)  -> Right $ FCVT_W_S  rdi rs1f rm
    (0x60, _, 1)  -> Right $ FCVT_WU_S rdi rs1f rm
    (0x60, _, 2)  -> Right $ FCVT_L_S  rdi rs1f rm
    (0x60, _, 3)  -> Right $ FCVT_LU_S rdi rs1f rm
    (0x68, _, 0)  -> Right $ FCVT_S_W  rd_ rs1i rm
    (0x68, _, 1)  -> Right $ FCVT_S_WU rd_ rs1i rm
    (0x68, _, 2)  -> Right $ FCVT_S_L  rd_ rs1i rm
    (0x68, _, 3)  -> Right $ FCVT_S_LU rd_ rs1i rm
    (0x70, 0, 0)  -> Right $ FMV_X_W   rdi rs1f
    (0x70, 1, 0)  -> Right $ FCLASS_S  rdi rs1f
    (0x78, 0, 0)  -> Right $ FMV_W_X   rd_ rs1i
    -- D variants
    (0x01, _, _)  -> Right $ FADD_D  rd_ rs1f rs2f rm
    (0x05, _, _)  -> Right $ FSUB_D  rd_ rs1f rs2f rm
    (0x09, _, _)  -> Right $ FMUL_D  rd_ rs1f rs2f rm
    (0x0D, _, _)  -> Right $ FDIV_D  rd_ rs1f rs2f rm
    (0x2D, _, 0)  -> Right $ FSQRT_D rd_ rs1f rm
    (0x11, 0, _)  -> Right $ FSGNJ_D  rd_ rs1f rs2f
    (0x11, 1, _)  -> Right $ FSGNJN_D rd_ rs1f rs2f
    (0x11, 2, _)  -> Right $ FSGNJX_D rd_ rs1f rs2f
    (0x15, 0, _)  -> Right $ FMIN_D  rd_ rs1f rs2f
    (0x15, 1, _)  -> Right $ FMAX_D  rd_ rs1f rs2f
    (0x20, _, 1)  -> Right $ FCVT_S_D rd_ rs1f rm
    (0x21, _, 0)  -> Right $ FCVT_D_S rd_ rs1f rm
    (0x51, 2, _)  -> Right $ FEQ_D   rdi rs1f rs2f
    (0x51, 1, _)  -> Right $ FLT_D   rdi rs1f rs2f
    (0x51, 0, _)  -> Right $ FLE_D   rdi rs1f rs2f
    (0x61, _, 0)  -> Right $ FCVT_W_D  rdi rs1f rm
    (0x61, _, 1)  -> Right $ FCVT_WU_D rdi rs1f rm
    (0x61, _, 2)  -> Right $ FCVT_L_D  rdi rs1f rm
    (0x61, _, 3)  -> Right $ FCVT_LU_D rdi rs1f rm
    (0x69, _, 0)  -> Right $ FCVT_D_W  rd_ rs1i rm
    (0x69, _, 1)  -> Right $ FCVT_D_WU rd_ rs1i rm
    (0x69, _, 2)  -> Right $ FCVT_D_L  rd_ rs1i rm
    (0x69, _, 3)  -> Right $ FCVT_D_LU rd_ rs1i rm
    (0x71, 0, 0)  -> Right $ FMV_X_D   rdi rs1f
    (0x71, 1, 0)  -> Right $ FCLASS_D  rdi rs1f
    (0x79, 0, 0)  -> Right $ FMV_D_X   rd_ rs1i
    _             -> Left  $ UnknownFunct7 0x53 f3 f7
