module Core.Encode (encode) where

import Core.Types
import Core.Instruction
import Data.Bits  (shiftL, shiftR, (.|.), (.&.))
import Data.Word  (Word32)

buildR :: Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32
buildR opcode rd funct3 rs1 rs2 funct7 =
  (funct7 `shiftL` 25) .|. (rs2 `shiftL` 20) .|. (rs1 `shiftL` 15)
  .|. (funct3 `shiftL` 12) .|. (rd `shiftL` 7) .|. opcode

buildI :: Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32
buildI opcode rd funct3 rs1 imm12 =
  ((imm12 .&. 0xFFF) `shiftL` 20) .|. (rs1 `shiftL` 15)
  .|. (funct3 `shiftL` 12) .|. (rd `shiftL` 7) .|. opcode

-- For RV64I shift-immediates: 6-bit shamt + 6-bit funct6 discriminator
buildIShift :: Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32
buildIShift opcode rd funct3 rs1 shamt funct6 =
  (funct6 `shiftL` 26) .|. ((shamt .&. 0x3F) `shiftL` 20)
  .|. (rs1 `shiftL` 15) .|. (funct3 `shiftL` 12) .|. (rd `shiftL` 7) .|. opcode

buildS :: Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32
buildS opcode funct3 rs1 rs2 imm12 =
  let i = imm12 .&. 0xFFF
  in  ((i `shiftR` 5) .&. 0x7F) `shiftL` 25 .|. (rs2 `shiftL` 20)
      .|. (rs1 `shiftL` 15) .|. (funct3 `shiftL` 12)
      .|. (i .&. 0x1F) `shiftL` 7 .|. opcode

buildB :: Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32
buildB opcode funct3 rs1 rs2 imm13 =
  let i = imm13 .&. 0x1FFF
  in  ((i `shiftR` 12) .&. 0x1) `shiftL` 31
      .|. ((i `shiftR` 5) .&. 0x3F) `shiftL` 25
      .|. (rs2 `shiftL` 20) .|. (rs1 `shiftL` 15)
      .|. (funct3 `shiftL` 12)
      .|. ((i `shiftR` 1) .&. 0xF) `shiftL` 8
      .|. ((i `shiftR` 11) .&. 0x1) `shiftL` 7
      .|. opcode

buildU :: Word32 -> Word32 -> Word32 -> Word32
buildU opcode rd imm20 =
  ((imm20 .&. 0xFFFFF) `shiftL` 12) .|. (rd `shiftL` 7) .|. opcode

buildJ :: Word32 -> Word32 -> Word32 -> Word32
buildJ opcode rd imm21 =
  let i = imm21 .&. 0x1FFFFF
  in  ((i `shiftR` 20) .&. 0x1) `shiftL` 31
      .|. ((i `shiftR` 1) .&. 0x3FF) `shiftL` 21
      .|. ((i `shiftR` 11) .&. 0x1) `shiftL` 20
      .|. ((i `shiftR` 12) .&. 0xFF) `shiftL` 12
      .|. (rd `shiftL` 7) .|. opcode

r :: Register -> Word32
r (Register x) = fromIntegral x

csr :: CSRAddr -> Word32
csr (CSRAddr x) = fromIntegral x

i12 :: Imm12 -> Word32
i12 (Imm12 x) = fromIntegral x

i13 :: Imm13 -> Word32
i13 (Imm13 x) = fromIntegral x

i20 :: Imm20 -> Word32
i20 (Imm20 x) = fromIntegral x

i21 :: Imm21 -> Word32
i21 (Imm21 x) = fromIntegral x

u5 :: UImm5 -> Word32
u5 (UImm5 x) = fromIntegral x

u6 :: UImm6 -> Word32
u6 (UImm6 x) = fromIntegral x

encodeAqRl :: AqRl -> (Word32, Word32)  -- (aq, rl)
encodeAqRl AqRlNone    = (0, 0)
encodeAqRl AqRlRelease = (0, 1)
encodeAqRl AqRlAcquire = (1, 0)
encodeAqRl AqRlAcqRel  = (1, 1)

-- Atomic Memory Operation: opcode=0x2F
-- funct5 aq rl rs2 rs1 funct3 rd
buildAMO :: Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32
buildAMO funct5 aq rl rs2W rs1W funct3 rdW =
  (funct5 `shiftL` 27) .|. (aq `shiftL` 26) .|. (rl `shiftL` 25)
  .|. (rs2W `shiftL` 20) .|. (rs1W `shiftL` 15)
  .|. (funct3 `shiftL` 12) .|. (rdW `shiftL` 7) .|. 0x2F

fr :: FPRegister -> Word32
fr (FPRegister x) = fromIntegral x

encodeRM :: RoundingMode -> Word32
encodeRM RNE = 0; encodeRM RTZ = 1; encodeRM RDN = 2
encodeRM RUP = 3; encodeRM RMM = 4; encodeRM DYN = 7

-- Standard FP operation: opcode=0x53
buildFPOp :: Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32
buildFPOp funct7 rs2W rs1W rmW rdW =
  (funct7 `shiftL` 25) .|. (rs2W `shiftL` 20) .|. (rs1W `shiftL` 15)
  .|. (rmW `shiftL` 12) .|. (rdW `shiftL` 7) .|. 0x53

-- R4 format: FMADD/FMSUB/FNMADD/FNMSUB
buildR4 :: Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32
buildR4 opcode rs3W fmt rs2W rs1W rmW rdW =
  (rs3W `shiftL` 27) .|. (fmt `shiftL` 25) .|. (rs2W `shiftL` 20)
  .|. (rs1W `shiftL` 15) .|. (rmW `shiftL` 12) .|. (rdW `shiftL` 7) .|. opcode

encode :: Instruction -> Word32
encode = \case
  ADD  rd rs1 rs2 -> buildR 0x33 (r rd) 0x0 (r rs1) (r rs2) 0x00
  SUB  rd rs1 rs2 -> buildR 0x33 (r rd) 0x0 (r rs1) (r rs2) 0x20
  ADDI rd rs1 imm -> buildI 0x13 (r rd) 0x0 (r rs1) (i12 imm)
  ADDIW rd rs1 imm -> buildI 0x1B (r rd) 0x0 (r rs1) (i12 imm)
  ADDW rd rs1 rs2 -> buildR 0x3B (r rd) 0x0 (r rs1) (r rs2) 0x00
  SUBW rd rs1 rs2 -> buildR 0x3B (r rd) 0x0 (r rs1) (r rs2) 0x20
  AND  rd rs1 rs2 -> buildR 0x33 (r rd) 0x7 (r rs1) (r rs2) 0x00
  OR   rd rs1 rs2 -> buildR 0x33 (r rd) 0x6 (r rs1) (r rs2) 0x00
  XOR  rd rs1 rs2 -> buildR 0x33 (r rd) 0x4 (r rs1) (r rs2) 0x00
  ANDI rd rs1 imm -> buildI 0x13 (r rd) 0x7 (r rs1) (i12 imm)
  ORI  rd rs1 imm -> buildI 0x13 (r rd) 0x6 (r rs1) (i12 imm)
  XORI rd rs1 imm -> buildI 0x13 (r rd) 0x4 (r rs1) (i12 imm)
  SLL  rd rs1 rs2 -> buildR 0x33 (r rd) 0x1 (r rs1) (r rs2) 0x00
  SRL  rd rs1 rs2 -> buildR 0x33 (r rd) 0x5 (r rs1) (r rs2) 0x00
  SRA  rd rs1 rs2 -> buildR 0x33 (r rd) 0x5 (r rs1) (r rs2) 0x20
  SLLI rd rs1 sh  -> buildIShift 0x13 (r rd) 0x1 (r rs1) (u6 sh) 0x00
  SRLI rd rs1 sh  -> buildIShift 0x13 (r rd) 0x5 (r rs1) (u6 sh) 0x00
  SRAI rd rs1 sh  -> buildIShift 0x13 (r rd) 0x5 (r rs1) (u6 sh) 0x10
  SLLIW rd rs1 sh -> buildR 0x1B (r rd) 0x1 (r rs1) (u5 sh) 0x00
  SRLIW rd rs1 sh -> buildR 0x1B (r rd) 0x5 (r rs1) (u5 sh) 0x00
  SRAIW rd rs1 sh -> buildR 0x1B (r rd) 0x5 (r rs1) (u5 sh) 0x20
  SLLW rd rs1 rs2 -> buildR 0x3B (r rd) 0x1 (r rs1) (r rs2) 0x00
  SRLW rd rs1 rs2 -> buildR 0x3B (r rd) 0x5 (r rs1) (r rs2) 0x00
  SRAW rd rs1 rs2 -> buildR 0x3B (r rd) 0x5 (r rs1) (r rs2) 0x20
  SLT  rd rs1 rs2 -> buildR 0x33 (r rd) 0x2 (r rs1) (r rs2) 0x00
  SLTU rd rs1 rs2 -> buildR 0x33 (r rd) 0x3 (r rs1) (r rs2) 0x00
  SLTI  rd rs1 imm -> buildI 0x13 (r rd) 0x2 (r rs1) (i12 imm)
  SLTIU rd rs1 imm -> buildI 0x13 (r rd) 0x3 (r rs1) (i12 imm)
  LUI   rd imm -> buildU 0x37 (r rd) (i20 imm)
  AUIPC rd imm -> buildU 0x17 (r rd) (i20 imm)
  LB  rd rs1 imm -> buildI 0x03 (r rd) 0x0 (r rs1) (i12 imm)
  LH  rd rs1 imm -> buildI 0x03 (r rd) 0x1 (r rs1) (i12 imm)
  LW  rd rs1 imm -> buildI 0x03 (r rd) 0x2 (r rs1) (i12 imm)
  LD  rd rs1 imm -> buildI 0x03 (r rd) 0x3 (r rs1) (i12 imm)
  LBU rd rs1 imm -> buildI 0x03 (r rd) 0x4 (r rs1) (i12 imm)
  LHU rd rs1 imm -> buildI 0x03 (r rd) 0x5 (r rs1) (i12 imm)
  LWU rd rs1 imm -> buildI 0x03 (r rd) 0x6 (r rs1) (i12 imm)
  SB rs2 rs1 imm -> buildS 0x23 0x0 (r rs1) (r rs2) (i12 imm)
  SH rs2 rs1 imm -> buildS 0x23 0x1 (r rs1) (r rs2) (i12 imm)
  SW rs2 rs1 imm -> buildS 0x23 0x2 (r rs1) (r rs2) (i12 imm)
  SD rs2 rs1 imm -> buildS 0x23 0x3 (r rs1) (r rs2) (i12 imm)
  BEQ  rs1 rs2 imm -> buildB 0x63 0x0 (r rs1) (r rs2) (i13 imm)
  BNE  rs1 rs2 imm -> buildB 0x63 0x1 (r rs1) (r rs2) (i13 imm)
  BLT  rs1 rs2 imm -> buildB 0x63 0x4 (r rs1) (r rs2) (i13 imm)
  BGE  rs1 rs2 imm -> buildB 0x63 0x5 (r rs1) (r rs2) (i13 imm)
  BLTU rs1 rs2 imm -> buildB 0x63 0x6 (r rs1) (r rs2) (i13 imm)
  BGEU rs1 rs2 imm -> buildB 0x63 0x7 (r rs1) (r rs2) (i13 imm)
  JAL  rd imm     -> buildJ 0x6F (r rd) (i21 imm)
  JALR rd rs1 imm -> buildI 0x67 (r rd) 0x0 (r rs1) (i12 imm)
  ECALL   -> buildI 0x73 0 0 0 0
  EBREAK  -> buildI 0x73 0 0 0 1
  FENCE_I -> buildI 0x0F 0 0x1 0 0
  FENCE pre suc ->
    -- bits[31:28]=fm (implicit 0000); bits[27:24]=pred; bits[23:20]=succ
    let encFm fm = (if fenceI fm then 8 else 0) .|. (if fenceO fm then 4 else 0)
                   .|. (if fenceR fm then 2 else 0) .|. (if fenceW fm then 1 else 0)
    in  (encFm pre `shiftL` 24) .|. (encFm suc `shiftL` 20) .|. 0x0F
  CSRRW  rd caddr rs1 -> buildI 0x73 (r rd) 0x1 (r rs1) (csr caddr)
  CSRRS  rd caddr rs1 -> buildI 0x73 (r rd) 0x2 (r rs1) (csr caddr)
  CSRRC  rd caddr rs1 -> buildI 0x73 (r rd) 0x3 (r rs1) (csr caddr)
  CSRRWI rd caddr imm -> buildI 0x73 (r rd) 0x5 (u5 imm) (csr caddr)
  CSRRSI rd caddr imm -> buildI 0x73 (r rd) 0x6 (u5 imm) (csr caddr)
  CSRRCI rd caddr imm -> buildI 0x73 (r rd) 0x7 (u5 imm) (csr caddr)
  MUL    rd rs1 rs2 -> buildR 0x33 (r rd) 0x0 (r rs1) (r rs2) 0x01
  MULH   rd rs1 rs2 -> buildR 0x33 (r rd) 0x1 (r rs1) (r rs2) 0x01
  MULHSU rd rs1 rs2 -> buildR 0x33 (r rd) 0x2 (r rs1) (r rs2) 0x01
  MULHU  rd rs1 rs2 -> buildR 0x33 (r rd) 0x3 (r rs1) (r rs2) 0x01
  DIV    rd rs1 rs2 -> buildR 0x33 (r rd) 0x4 (r rs1) (r rs2) 0x01
  DIVU   rd rs1 rs2 -> buildR 0x33 (r rd) 0x5 (r rs1) (r rs2) 0x01
  REM    rd rs1 rs2 -> buildR 0x33 (r rd) 0x6 (r rs1) (r rs2) 0x01
  REMU   rd rs1 rs2 -> buildR 0x33 (r rd) 0x7 (r rs1) (r rs2) 0x01
  MULW   rd rs1 rs2 -> buildR 0x3B (r rd) 0x0 (r rs1) (r rs2) 0x01
  DIVW   rd rs1 rs2 -> buildR 0x3B (r rd) 0x4 (r rs1) (r rs2) 0x01
  DIVUW  rd rs1 rs2 -> buildR 0x3B (r rd) 0x5 (r rs1) (r rs2) 0x01
  REMW   rd rs1 rs2 -> buildR 0x3B (r rd) 0x6 (r rs1) (r rs2) 0x01
  REMUW  rd rs1 rs2 -> buildR 0x3B (r rd) 0x7 (r rs1) (r rs2) 0x01
  MRET -> buildR 0x73 0 0 0 2 0x18
  SRET -> buildR 0x73 0 0 0 2 0x08
  WFI  -> buildR 0x73 0 0 0 5 0x08
  SFENCE_VMA rs1 rs2 -> buildR 0x73 0 0 (r rs1) (r rs2) 0x09
  -- ── RV64A ─────────────────────────────────────────────────────
  LR_W  rd rs1 aq     -> let (a,l) = encodeAqRl aq in buildAMO 0x02 a l 0        (r rs1) 0x2 (r rd)
  LR_D  rd rs1 aq     -> let (a,l) = encodeAqRl aq in buildAMO 0x02 a l 0        (r rs1) 0x3 (r rd)
  SC_W  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x03 a l (r rs2) (r rs1) 0x2 (r rd)
  SC_D  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x03 a l (r rs2) (r rs1) 0x3 (r rd)
  AMOSWAP_W rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x01 a l (r rs2) (r rs1) 0x2 (r rd)
  AMOADD_W  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x00 a l (r rs2) (r rs1) 0x2 (r rd)
  AMOXOR_W  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x04 a l (r rs2) (r rs1) 0x2 (r rd)
  AMOAND_W  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x0C a l (r rs2) (r rs1) 0x2 (r rd)
  AMOOR_W   rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x08 a l (r rs2) (r rs1) 0x2 (r rd)
  AMOMIN_W  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x10 a l (r rs2) (r rs1) 0x2 (r rd)
  AMOMAX_W  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x14 a l (r rs2) (r rs1) 0x2 (r rd)
  AMOMINU_W rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x18 a l (r rs2) (r rs1) 0x2 (r rd)
  AMOMAXU_W rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x1C a l (r rs2) (r rs1) 0x2 (r rd)
  AMOSWAP_D rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x01 a l (r rs2) (r rs1) 0x3 (r rd)
  AMOADD_D  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x00 a l (r rs2) (r rs1) 0x3 (r rd)
  AMOXOR_D  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x04 a l (r rs2) (r rs1) 0x3 (r rd)
  AMOAND_D  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x0C a l (r rs2) (r rs1) 0x3 (r rd)
  AMOOR_D   rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x08 a l (r rs2) (r rs1) 0x3 (r rd)
  AMOMIN_D  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x10 a l (r rs2) (r rs1) 0x3 (r rd)
  AMOMAX_D  rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x14 a l (r rs2) (r rs1) 0x3 (r rd)
  AMOMINU_D rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x18 a l (r rs2) (r rs1) 0x3 (r rd)
  AMOMAXU_D rd rs1 rs2 aq -> let (a,l) = encodeAqRl aq in buildAMO 0x1C a l (r rs2) (r rs1) 0x3 (r rd)
  -- ── RV64F ─────────────────────────────────────────────────────
  FLW  rd rs1 imm -> buildI 0x07 (fr rd) 0x2 (r rs1) (i12 imm)
  FSW  rs2 rs1 imm -> buildS 0x27 0x2 (r rs1) (fr rs2) (i12 imm)
  FMADD_S  rd rs1 rs2 rs3 rm -> buildR4 0x43 (fr rs3) 0x0 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FMSUB_S  rd rs1 rs2 rs3 rm -> buildR4 0x47 (fr rs3) 0x0 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FNMSUB_S rd rs1 rs2 rs3 rm -> buildR4 0x4B (fr rs3) 0x0 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FNMADD_S rd rs1 rs2 rs3 rm -> buildR4 0x4F (fr rs3) 0x0 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FADD_S  rd rs1 rs2 rm -> buildFPOp 0x00 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FSUB_S  rd rs1 rs2 rm -> buildFPOp 0x04 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FMUL_S  rd rs1 rs2 rm -> buildFPOp 0x08 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FDIV_S  rd rs1 rs2 rm -> buildFPOp 0x0C (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FSQRT_S rd rs1 rm     -> buildFPOp 0x2C 0          (fr rs1) (encodeRM rm) (fr rd)
  FSGNJ_S  rd rs1 rs2   -> buildFPOp 0x10 (fr rs2) (fr rs1) 0x0 (fr rd)
  FSGNJN_S rd rs1 rs2   -> buildFPOp 0x10 (fr rs2) (fr rs1) 0x1 (fr rd)
  FSGNJX_S rd rs1 rs2   -> buildFPOp 0x10 (fr rs2) (fr rs1) 0x2 (fr rd)
  FMIN_S   rd rs1 rs2   -> buildFPOp 0x14 (fr rs2) (fr rs1) 0x0 (fr rd)
  FMAX_S   rd rs1 rs2   -> buildFPOp 0x14 (fr rs2) (fr rs1) 0x1 (fr rd)
  FCVT_W_S  rd rs1 rm -> buildFPOp 0x60 0x00 (fr rs1) (encodeRM rm) (r rd)
  FCVT_WU_S rd rs1 rm -> buildFPOp 0x60 0x01 (fr rs1) (encodeRM rm) (r rd)
  FCVT_L_S  rd rs1 rm -> buildFPOp 0x60 0x02 (fr rs1) (encodeRM rm) (r rd)
  FCVT_LU_S rd rs1 rm -> buildFPOp 0x60 0x03 (fr rs1) (encodeRM rm) (r rd)
  FCVT_S_W  rd rs1 rm -> buildFPOp 0x68 0x00 (r rs1) (encodeRM rm) (fr rd)
  FCVT_S_WU rd rs1 rm -> buildFPOp 0x68 0x01 (r rs1) (encodeRM rm) (fr rd)
  FCVT_S_L  rd rs1 rm -> buildFPOp 0x68 0x02 (r rs1) (encodeRM rm) (fr rd)
  FCVT_S_LU rd rs1 rm -> buildFPOp 0x68 0x03 (r rs1) (encodeRM rm) (fr rd)
  FMV_X_W   rd rs1    -> buildFPOp 0x70 0x00 (fr rs1) 0x0 (r rd)
  FMV_W_X   rd rs1    -> buildFPOp 0x78 0x00 (r rs1) 0x0 (fr rd)
  FEQ_S     rd rs1 rs2 -> buildFPOp 0x50 (fr rs2) (fr rs1) 0x2 (r rd)
  FLT_S     rd rs1 rs2 -> buildFPOp 0x50 (fr rs2) (fr rs1) 0x1 (r rd)
  FLE_S     rd rs1 rs2 -> buildFPOp 0x50 (fr rs2) (fr rs1) 0x0 (r rd)
  FCLASS_S  rd rs1     -> buildFPOp 0x70 0x00 (fr rs1) 0x1 (r rd)
  -- ── RV64D ─────────────────────────────────────────────────────
  FLD  rd rs1 imm -> buildI 0x07 (fr rd) 0x3 (r rs1) (i12 imm)
  FSD  rs2 rs1 imm -> buildS 0x27 0x3 (r rs1) (fr rs2) (i12 imm)
  FMADD_D  rd rs1 rs2 rs3 rm -> buildR4 0x43 (fr rs3) 0x1 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FMSUB_D  rd rs1 rs2 rs3 rm -> buildR4 0x47 (fr rs3) 0x1 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FNMSUB_D rd rs1 rs2 rs3 rm -> buildR4 0x4B (fr rs3) 0x1 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FNMADD_D rd rs1 rs2 rs3 rm -> buildR4 0x4F (fr rs3) 0x1 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FADD_D  rd rs1 rs2 rm -> buildFPOp 0x01 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FSUB_D  rd rs1 rs2 rm -> buildFPOp 0x05 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FMUL_D  rd rs1 rs2 rm -> buildFPOp 0x09 (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FDIV_D  rd rs1 rs2 rm -> buildFPOp 0x0D (fr rs2) (fr rs1) (encodeRM rm) (fr rd)
  FSQRT_D rd rs1 rm     -> buildFPOp 0x2D 0          (fr rs1) (encodeRM rm) (fr rd)
  FSGNJ_D  rd rs1 rs2   -> buildFPOp 0x11 (fr rs2) (fr rs1) 0x0 (fr rd)
  FSGNJN_D rd rs1 rs2   -> buildFPOp 0x11 (fr rs2) (fr rs1) 0x1 (fr rd)
  FSGNJX_D rd rs1 rs2   -> buildFPOp 0x11 (fr rs2) (fr rs1) 0x2 (fr rd)
  FMIN_D   rd rs1 rs2   -> buildFPOp 0x15 (fr rs2) (fr rs1) 0x0 (fr rd)
  FMAX_D   rd rs1 rs2   -> buildFPOp 0x15 (fr rs2) (fr rs1) 0x1 (fr rd)
  FCVT_S_D rd rs1 rm -> buildFPOp 0x20 0x01 (fr rs1) (encodeRM rm) (fr rd)
  FCVT_D_S rd rs1 rm -> buildFPOp 0x21 0x00 (fr rs1) (encodeRM rm) (fr rd)
  FCVT_W_D  rd rs1 rm -> buildFPOp 0x61 0x00 (fr rs1) (encodeRM rm) (r rd)
  FCVT_WU_D rd rs1 rm -> buildFPOp 0x61 0x01 (fr rs1) (encodeRM rm) (r rd)
  FCVT_L_D  rd rs1 rm -> buildFPOp 0x61 0x02 (fr rs1) (encodeRM rm) (r rd)
  FCVT_LU_D rd rs1 rm -> buildFPOp 0x61 0x03 (fr rs1) (encodeRM rm) (r rd)
  FCVT_D_W  rd rs1 rm -> buildFPOp 0x69 0x00 (r rs1) (encodeRM rm) (fr rd)
  FCVT_D_WU rd rs1 rm -> buildFPOp 0x69 0x01 (r rs1) (encodeRM rm) (fr rd)
  FCVT_D_L  rd rs1 rm -> buildFPOp 0x69 0x02 (r rs1) (encodeRM rm) (fr rd)
  FCVT_D_LU rd rs1 rm -> buildFPOp 0x69 0x03 (r rs1) (encodeRM rm) (fr rd)
  FMV_X_D   rd rs1    -> buildFPOp 0x71 0x00 (fr rs1) 0x0 (r rd)
  FMV_D_X   rd rs1    -> buildFPOp 0x79 0x00 (r rs1) 0x0 (fr rd)
  FEQ_D     rd rs1 rs2 -> buildFPOp 0x51 (fr rs2) (fr rs1) 0x2 (r rd)
  FLT_D     rd rs1 rs2 -> buildFPOp 0x51 (fr rs2) (fr rs1) 0x1 (r rd)
  FLE_D     rd rs1 rs2 -> buildFPOp 0x51 (fr rs2) (fr rs1) 0x0 (r rd)
  FCLASS_D  rd rs1     -> buildFPOp 0x71 0x00 (fr rs1) 0x1 (r rd)
