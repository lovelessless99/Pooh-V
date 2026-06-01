module Core.Decode
  ( decode
  , decode16
  , DecodeError(..)
  ) where

import Core.Types
import Core.Instruction
import Data.Bits  (shiftL, shiftR, (.|.), (.&.), testBit)
import Data.Word  (Word16, Word32)
import Data.Int   (Int8, Int16, Int32)

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

-- Helper: 3-bit compressed register field → Register (0→x8, 7→x15)
mkCReg :: Word16 -> Register
mkCReg x = Register (fromIntegral x + 8)

cField :: Word16 -> Int -> Int -> Word16
cField w hi lo = (w `shiftR` lo) .&. ((1 `shiftL` (hi - lo + 1)) - 1)

signExt6C :: Word16 -> Int8
signExt6C v =
  let raw = fromIntegral (v .&. 0x3F) :: Int8
  in if raw .&. 0x20 /= 0 then raw - 64 else raw

decode16 :: Word16 -> Either DecodeError Instruction
decode16 w =
  let quad   = w .&. 0x3
      funct3 = cField w 15 13
  in case quad of
    0x0 -> decodeQ0 w funct3
    0x1 -> decodeQ1 w funct3
    0x2 -> decodeQ2 w funct3
    _   -> Left (ReservedEncoding (fromIntegral w))

decodeQ0 :: Word16 -> Word16 -> Either DecodeError Instruction
decodeQ0 w funct3 =
  let rd'_  = mkCReg (cField w 4 2)
      rs1'_ = mkCReg (cField w 9 7)
      rs2'_ = mkCReg (cField w 4 2)
  in case funct3 of
    0x0 ->
      -- C.ADDI4SPN: nzuimm[5:4]→[12:11],[9:6]→[10:7],[2]→[6],[3]→[5]
      let b5_4 = cField w 12 11
          b9_6 = cField w 10 7
          b2   = cField w 6 6
          b3   = cField w 5 5
          nzuimm = (b9_6 `shiftL` 6) .|. (b5_4 `shiftL` 4) .|. (b3 `shiftL` 3) .|. (b2 `shiftL` 2)
      in Right $ C_ADDI4SPN rd'_ (UImm10 nzuimm)
    0x2 ->
      -- C.LW: uimm[5:3]→[12:10],[2]→[6],[6]→[5]
      let b5_3 = cField w 12 10
          b2   = cField w 6 6
          b6   = cField w 5 5
          uimm = (b6 `shiftL` 6) .|. (b5_3 `shiftL` 3) .|. (b2 `shiftL` 2)
      in Right $ C_LW rd'_ rs1'_ (UImm7 (fromIntegral uimm))
    0x3 ->
      -- C.LD: uimm[5:3]→[12:10],[7:6]→[6:5]
      let b5_3 = cField w 12 10
          b7_6 = cField w 6 5
          uimm = (b7_6 `shiftL` 6) .|. (b5_3 `shiftL` 3)
      in Right $ C_LD rd'_ rs1'_ (UImm8 (fromIntegral uimm))
    0x6 ->
      -- C.SW: same bit layout as C.LW but stores
      let b5_3 = cField w 12 10
          b2   = cField w 6 6
          b6   = cField w 5 5
          uimm = (b6 `shiftL` 6) .|. (b5_3 `shiftL` 3) .|. (b2 `shiftL` 2)
      in Right $ C_SW rs1'_ rs2'_ (UImm7 (fromIntegral uimm))
    0x7 ->
      -- C.SD: same as C.LD but stores
      let b5_3 = cField w 12 10
          b7_6 = cField w 6 5
          uimm = (b7_6 `shiftL` 6) .|. (b5_3 `shiftL` 3)
      in Right $ C_SD rs1'_ rs2'_ (UImm8 (fromIntegral uimm))
    f   -> Left (UnknownFunct3 0x0 (fromIntegral f))

decodeQ1 :: Word16 -> Word16 -> Either DecodeError Instruction
decodeQ1 w funct3 =
  let rdrs1  = Register (fromIntegral (cField w 11 7))
      rd'c   = mkCReg (cField w 9 7)
      rs2'c  = mkCReg (cField w 4 2)
      rawImm6 = (cField w 12 12 `shiftL` 5) .|. cField w 6 2
      imm6    = Imm6 (signExt6C rawImm6)
  in case funct3 of
    0x0 -> Right $ C_ADDI rdrs1 imm6
    0x1 -> Right $ C_ADDIW rdrs1 imm6
    0x2 -> Right $ C_LI rdrs1 imm6
    0x3 ->
      let rd5 = cField w 11 7
      in if rd5 == 2
         then
           -- C.ADDI16SP: nzimm[9]→[12],[4]→[6],[6]→[5],[8:7]→[4:3],[5]→[2]
           let b9   = cField w 12 12
               b4   = cField w 6 6
               b6   = cField w 5 5
               b8_7 = cField w 4 3
               b5   = cField w 2 2
               nzimm = (b9 `shiftL` 9) .|. (b8_7 `shiftL` 7) .|. (b6 `shiftL` 6)
                     .|. (b5 `shiftL` 5) .|. (b4 `shiftL` 4)
               sv = fromIntegral (if nzimm .&. 0x200 /= 0 then fromIntegral nzimm - (0x400 :: Int) else fromIntegral nzimm) :: Int16
           in Right $ C_ADDI16SP (Imm10 sv)
         else Right $ C_LUI rdrs1 imm6
    0x4 ->
      let funct2 = cField w 11 10
          bit12  = cField w 12 12
          rawSh  = (bit12 `shiftL` 5) .|. cField w 6 2
      in case (funct2, bit12) of
        (0x0, _) -> Right $ C_SRLI rd'c (UImm6 (fromIntegral rawSh))
        (0x1, _) -> Right $ C_SRAI rd'c (UImm6 (fromIntegral rawSh))
        (0x2, _) -> Right $ C_ANDI rd'c (Imm6 (signExt6C rawSh))
        (0x3, 0) ->
          let sub3 = cField w 6 5
          in case sub3 of
            0x0 -> Right $ C_SUB  rd'c rs2'c
            0x1 -> Right $ C_XOR  rd'c rs2'c
            0x2 -> Right $ C_OR   rd'c rs2'c
            0x3 -> Right $ C_AND  rd'c rs2'c
            _   -> Left (ReservedEncoding (fromIntegral w))
        (0x3, 1) ->
          let sub3 = cField w 6 5
          in case sub3 of
            0x0 -> Right $ C_SUBW rd'c rs2'c
            0x1 -> Right $ C_ADDW rd'c rs2'c
            _   -> Left (ReservedEncoding (fromIntegral w))
        _ -> Left (ReservedEncoding (fromIntegral w))
    0x5 ->
      -- C.J: j[11]|j[4]|j[9:8]|j[10]|j[6]|j[7]|j[3:1]|j[5] in bits[12:2]
      let raw  = cField w 12 2   -- 11-bit value
          b11  = (raw `shiftR` 10) .&. 0x1
          b4   = (raw `shiftR` 9)  .&. 0x1
          b9_8 = (raw `shiftR` 7)  .&. 0x3
          b10  = (raw `shiftR` 6)  .&. 0x1
          b6   = (raw `shiftR` 5)  .&. 0x1
          b7   = (raw `shiftR` 4)  .&. 0x1
          b3_1 = (raw `shiftR` 1)  .&. 0x7
          b5   = raw               .&. 0x1
          target = (b11 `shiftL` 11) .|. (b10 `shiftL` 10) .|. (b9_8 `shiftL` 8)
                 .|. (b7 `shiftL` 7)  .|. (b6 `shiftL` 6)  .|. (b5 `shiftL` 5)
                 .|. (b4 `shiftL` 4)  .|. (b3_1 `shiftL` 1)
          sv = fromIntegral (if b11 /= 0 then fromIntegral target - (0x1000 :: Int) else fromIntegral target) :: Int16
      in Right $ C_J (Imm12 sv)
    0x6 ->
      -- C.BEQZ: offset[8]→[12],[4:3]→[11:10],[7:6]→[6:5],[2:1]→[4:3],[5]→[2]
      let rs1c = mkCReg (cField w 9 7)
          b8   = cField w 12 12
          b4_3 = cField w 11 10
          b7_6 = cField w 6 5
          b2_1 = cField w 4 3
          b5   = cField w 2 2
          v    = (b8 `shiftL` 8) .|. (b7_6 `shiftL` 6) .|. (b5 `shiftL` 5)
               .|. (b4_3 `shiftL` 3) .|. (b2_1 `shiftL` 1)
          sv   = fromIntegral (if b8 /= 0 then fromIntegral v - (0x200 :: Int) else fromIntegral v) :: Int16
      in Right $ C_BEQZ rs1c (Imm9 sv)
    0x7 ->
      let rs1c = mkCReg (cField w 9 7)
          b8   = cField w 12 12
          b4_3 = cField w 11 10
          b7_6 = cField w 6 5
          b2_1 = cField w 4 3
          b5   = cField w 2 2
          v    = (b8 `shiftL` 8) .|. (b7_6 `shiftL` 6) .|. (b5 `shiftL` 5)
               .|. (b4_3 `shiftL` 3) .|. (b2_1 `shiftL` 1)
          sv   = fromIntegral (if b8 /= 0 then fromIntegral v - (0x200 :: Int) else fromIntegral v) :: Int16
      in Right $ C_BNEZ rs1c (Imm9 sv)
    f   -> Left (UnknownFunct3 0x1 (fromIntegral f))

decodeQ2 :: Word16 -> Word16 -> Either DecodeError Instruction
decodeQ2 w funct3 =
  let rdrs1 = Register (fromIntegral (cField w 11 7))
      rs2   = Register (fromIntegral (cField w 6 2))
      bit12 = cField w 12 12
  in case funct3 of
    0x0 ->
      -- C.SLLI: shamt[5]→[12], shamt[4:0]→[6:2]
      let shamt = (bit12 `shiftL` 5) .|. cField w 6 2
      in Right $ C_SLLI rdrs1 (UImm6 (fromIntegral shamt))
    0x2 ->
      -- C.LWSP: uimm[5]→[12], uimm[4:2]→[6:4], uimm[7:6]→[3:2]
      let b5   = bit12
          b4_2 = cField w 6 4
          b7_6 = cField w 3 2
          uimm = (b7_6 `shiftL` 6) .|. (b5 `shiftL` 5) .|. (b4_2 `shiftL` 2)
      in Right $ C_LWSP rdrs1 (UImm8 (fromIntegral uimm))
    0x3 ->
      -- C.LDSP: uimm[5]→[12], uimm[4:3]→[6:5], uimm[8:6]→[4:2]
      let b5   = bit12
          b4_3 = cField w 6 5
          b8_6 = cField w 4 2
          uimm = (b8_6 `shiftL` 6) .|. (b5 `shiftL` 5) .|. (b4_3 `shiftL` 3)
      in Right $ C_LDSP rdrs1 (UImm9 (fromIntegral uimm))
    0x4 ->
      let rs2val = fromIntegral (cField w 6 2) :: Int
      in case (bit12, unReg rdrs1, rs2val) of
        (0, _, 0) -> Right $ C_JR rdrs1
        (0, _, _) -> Right $ C_MV rdrs1 rs2
        (1, 0, 0) -> Right C_EBREAK
        (1, _, 0) -> Right $ C_JALR rdrs1
        (1, _, _) -> Right $ C_ADD rdrs1 rs2
        _         -> Left (ReservedEncoding (fromIntegral w))
    0x6 ->
      -- C.SWSP: uimm[5:2]→[12:9], uimm[7:6]→[8:7]
      let b5_2 = cField w 12 9
          b7_6 = cField w 8 7
          uimm = (b7_6 `shiftL` 6) .|. (b5_2 `shiftL` 2)
      in Right $ C_SWSP rs2 (UImm8 (fromIntegral uimm))
    0x7 ->
      -- C.SDSP: uimm[5:3]→[12:10], uimm[8:6]→[9:7]
      let b5_3 = cField w 12 10
          b8_6 = cField w 9 7
          uimm = (b8_6 `shiftL` 6) .|. (b5_3 `shiftL` 3)
      in Right $ C_SDSP rs2 (UImm9 (fromIntegral uimm))
    f   -> Left (UnknownFunct3 0x2 (fromIntegral f))
