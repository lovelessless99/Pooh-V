module Core.Instruction
  ( Instruction(..)
  , Extension(..)
  , InstrFormat(..)
  , instrExtension
  , instrFormat
  , isRV64I, isRV64M, isPrivileged
  , requiresExtensions
  ) where

import Core.Types
import GHC.Generics (Generic)

data Extension
  = RV64I
  | RV64M
  | RV64A
  | RV64F
  | RV64D
  | RV64C
  | RVPriv
  deriving (Show, Eq, Ord, Enum, Bounded, Generic)

data InstrFormat
  = RFormat
  | IFormat
  | SFormat
  | BFormat
  | UFormat
  | JFormat
  deriving (Show, Eq, Ord, Enum, Bounded, Generic)

data Instruction
  -- ── RV64I: Arithmetic ──────────────────────────────────────────
  = ADD    Register Register Register
  | SUB    Register Register Register
  | ADDI   Register Register Imm12
  | ADDIW  Register Register Imm12
  | ADDW   Register Register Register
  | SUBW   Register Register Register
  -- ── RV64I: Logical ─────────────────────────────────────────────
  | AND    Register Register Register
  | OR     Register Register Register
  | XOR    Register Register Register
  | ANDI   Register Register Imm12
  | ORI    Register Register Imm12
  | XORI   Register Register Imm12
  -- ── RV64I: Shift ───────────────────────────────────────────────
  | SLL    Register Register Register
  | SRL    Register Register Register
  | SRA    Register Register Register
  | SLLI   Register Register UImm6
  | SRLI   Register Register UImm6
  | SRAI   Register Register UImm6
  | SLLIW  Register Register UImm5
  | SRLIW  Register Register UImm5
  | SRAIW  Register Register UImm5
  | SLLW   Register Register Register
  | SRLW   Register Register Register
  | SRAW   Register Register Register
  -- ── RV64I: Compare ─────────────────────────────────────────────
  | SLT    Register Register Register
  | SLTU   Register Register Register
  | SLTI   Register Register Imm12
  | SLTIU  Register Register Imm12
  -- ── RV64I: Upper Immediate ─────────────────────────────────────
  | LUI    Register Imm20
  | AUIPC  Register Imm20
  -- ── RV64I: Load ────────────────────────────────────────────────
  | LB     Register Register Imm12
  | LH     Register Register Imm12
  | LW     Register Register Imm12
  | LD     Register Register Imm12
  | LBU    Register Register Imm12
  | LHU    Register Register Imm12
  | LWU    Register Register Imm12
  -- ── RV64I: Store ───────────────────────────────────────────────
  | SB     Register Register Imm12
  | SH     Register Register Imm12
  | SW     Register Register Imm12
  | SD     Register Register Imm12
  -- ── RV64I: Branch ──────────────────────────────────────────────
  | BEQ    Register Register Imm13
  | BNE    Register Register Imm13
  | BLT    Register Register Imm13
  | BGE    Register Register Imm13
  | BLTU   Register Register Imm13
  | BGEU   Register Register Imm13
  -- ── RV64I: Jump ────────────────────────────────────────────────
  | JAL    Register Imm21
  | JALR   Register Register Imm12
  -- ── RV64I: System ──────────────────────────────────────────────
  | ECALL
  | EBREAK
  | FENCE  FenceMode FenceMode
  | FENCE_I
  -- ── RV64I: CSR ─────────────────────────────────────────────────
  | CSRRW  Register CSRAddr Register
  | CSRRS  Register CSRAddr Register
  | CSRRC  Register CSRAddr Register
  | CSRRWI Register CSRAddr UImm5
  | CSRRSI Register CSRAddr UImm5
  | CSRRCI Register CSRAddr UImm5
  -- ── RV64M: Multiply ────────────────────────────────────────────
  | MUL    Register Register Register
  | MULH   Register Register Register
  | MULHSU Register Register Register
  | MULHU  Register Register Register
  | DIV    Register Register Register
  | DIVU   Register Register Register
  | REM    Register Register Register
  | REMU   Register Register Register
  | MULW   Register Register Register
  | DIVW   Register Register Register
  | DIVUW  Register Register Register
  | REMW   Register Register Register
  | REMUW  Register Register Register
  -- ── Privileged ─────────────────────────────────────────────────
  | MRET
  | SRET
  | WFI
  | SFENCE_VMA Register Register      -- rs1=vaddr, rs2=asid
  -- ── RV64A: Load-Reserved / Store-Conditional ────────────────────
  | LR_W      Register Register AqRl          -- rd rs1 aqrl
  | LR_D      Register Register AqRl
  | SC_W      Register Register Register AqRl  -- rd rs1 rs2 aqrl
  | SC_D      Register Register Register AqRl
  -- ── RV64A: Atomic Memory Operations (word) ─────────────────────
  | AMOSWAP_W Register Register Register AqRl  -- rd rs1 rs2 aqrl
  | AMOADD_W  Register Register Register AqRl
  | AMOXOR_W  Register Register Register AqRl
  | AMOAND_W  Register Register Register AqRl
  | AMOOR_W   Register Register Register AqRl
  | AMOMIN_W  Register Register Register AqRl
  | AMOMAX_W  Register Register Register AqRl
  | AMOMINU_W Register Register Register AqRl
  | AMOMAXU_W Register Register Register AqRl
  -- ── RV64A: Atomic Memory Operations (double) ───────────────────
  | AMOSWAP_D Register Register Register AqRl
  | AMOADD_D  Register Register Register AqRl
  | AMOXOR_D  Register Register Register AqRl
  | AMOAND_D  Register Register Register AqRl
  | AMOOR_D   Register Register Register AqRl
  | AMOMIN_D  Register Register Register AqRl
  | AMOMAX_D  Register Register Register AqRl
  | AMOMINU_D Register Register Register AqRl
  | AMOMAXU_D Register Register Register AqRl
  -- ── RV64F: Loads / Stores ───────────────────────────────────────
  | FLW   FPRegister Register Imm12      -- rd rs1 offset
  | FSW   FPRegister Register Imm12      -- rs2 rs1 offset (rs2=data, rs1=base)
  -- ── RV64F: Fused Multiply-Add (R4 format) ──────────────────────
  | FMADD_S  FPRegister FPRegister FPRegister FPRegister RoundingMode
  | FMSUB_S  FPRegister FPRegister FPRegister FPRegister RoundingMode
  | FNMADD_S FPRegister FPRegister FPRegister FPRegister RoundingMode
  | FNMSUB_S FPRegister FPRegister FPRegister FPRegister RoundingMode
  -- ── RV64F: 3-Operand (OP-FP) ───────────────────────────────────
  | FADD_S   FPRegister FPRegister FPRegister RoundingMode
  | FSUB_S   FPRegister FPRegister FPRegister RoundingMode
  | FMUL_S   FPRegister FPRegister FPRegister RoundingMode
  | FDIV_S   FPRegister FPRegister FPRegister RoundingMode
  | FSQRT_S  FPRegister FPRegister RoundingMode
  | FSGNJ_S  FPRegister FPRegister FPRegister
  | FSGNJN_S FPRegister FPRegister FPRegister
  | FSGNJX_S FPRegister FPRegister FPRegister
  | FMIN_S   FPRegister FPRegister FPRegister
  | FMAX_S   FPRegister FPRegister FPRegister
  -- ── RV64F: Conversions ─────────────────────────────────────────
  | FCVT_W_S  Register FPRegister RoundingMode
  | FCVT_WU_S Register FPRegister RoundingMode
  | FCVT_L_S  Register FPRegister RoundingMode
  | FCVT_LU_S Register FPRegister RoundingMode
  | FCVT_S_W  FPRegister Register RoundingMode
  | FCVT_S_WU FPRegister Register RoundingMode
  | FCVT_S_L  FPRegister Register RoundingMode
  | FCVT_S_LU FPRegister Register RoundingMode
  -- ── RV64F: Move / Compare / Classify ───────────────────────────
  | FMV_X_W   Register FPRegister
  | FMV_W_X   FPRegister Register
  | FEQ_S     Register FPRegister FPRegister
  | FLT_S     Register FPRegister FPRegister
  | FLE_S     Register FPRegister FPRegister
  | FCLASS_S  Register FPRegister
  -- ── RV64D: Loads / Stores ───────────────────────────────────────
  | FLD   FPRegister Register Imm12
  | FSD   FPRegister Register Imm12
  -- ── RV64D: Fused Multiply-Add ──────────────────────────────────
  | FMADD_D  FPRegister FPRegister FPRegister FPRegister RoundingMode
  | FMSUB_D  FPRegister FPRegister FPRegister FPRegister RoundingMode
  | FNMADD_D FPRegister FPRegister FPRegister FPRegister RoundingMode
  | FNMSUB_D FPRegister FPRegister FPRegister FPRegister RoundingMode
  -- ── RV64D: 3-Operand ───────────────────────────────────────────
  | FADD_D   FPRegister FPRegister FPRegister RoundingMode
  | FSUB_D   FPRegister FPRegister FPRegister RoundingMode
  | FMUL_D   FPRegister FPRegister FPRegister RoundingMode
  | FDIV_D   FPRegister FPRegister FPRegister RoundingMode
  | FSQRT_D  FPRegister FPRegister RoundingMode
  | FSGNJ_D  FPRegister FPRegister FPRegister
  | FSGNJN_D FPRegister FPRegister FPRegister
  | FSGNJX_D FPRegister FPRegister FPRegister
  | FMIN_D   FPRegister FPRegister FPRegister
  | FMAX_D   FPRegister FPRegister FPRegister
  -- ── RV64D: Conversions ─────────────────────────────────────────
  | FCVT_S_D FPRegister FPRegister RoundingMode
  | FCVT_D_S FPRegister FPRegister RoundingMode
  | FCVT_W_D  Register FPRegister RoundingMode
  | FCVT_WU_D Register FPRegister RoundingMode
  | FCVT_L_D  Register FPRegister RoundingMode
  | FCVT_LU_D Register FPRegister RoundingMode
  | FCVT_D_W  FPRegister Register RoundingMode
  | FCVT_D_WU FPRegister Register RoundingMode
  | FCVT_D_L  FPRegister Register RoundingMode
  | FCVT_D_LU FPRegister Register RoundingMode
  -- ── RV64D: Move / Compare / Classify ───────────────────────────
  | FMV_X_D   Register FPRegister
  | FMV_D_X   FPRegister Register
  | FEQ_D     Register FPRegister FPRegister
  | FLT_D     Register FPRegister FPRegister
  | FLE_D     Register FPRegister FPRegister
  | FCLASS_D  Register FPRegister
  deriving (Show, Eq, Ord, Generic)

instrExtension :: Instruction -> Extension
instrExtension instr = case instr of
  MUL{}    -> RV64M; MULH{}   -> RV64M; MULHSU{} -> RV64M; MULHU{}  -> RV64M
  DIV{}    -> RV64M; DIVU{}   -> RV64M; REM{}     -> RV64M; REMU{}   -> RV64M
  MULW{}   -> RV64M; DIVW{}   -> RV64M; DIVUW{}   -> RV64M; REMW{}   -> RV64M
  REMUW{}  -> RV64M
  MRET     -> RVPriv; SRET -> RVPriv; WFI -> RVPriv; SFENCE_VMA{} -> RVPriv
  LR_W{} -> RV64A; LR_D{} -> RV64A
  SC_W{} -> RV64A; SC_D{} -> RV64A
  AMOSWAP_W{} -> RV64A; AMOADD_W{}  -> RV64A; AMOXOR_W{}  -> RV64A
  AMOAND_W{}  -> RV64A; AMOOR_W{}   -> RV64A; AMOMIN_W{}  -> RV64A
  AMOMAX_W{}  -> RV64A; AMOMINU_W{} -> RV64A; AMOMAXU_W{} -> RV64A
  AMOSWAP_D{} -> RV64A; AMOADD_D{}  -> RV64A; AMOXOR_D{}  -> RV64A
  AMOAND_D{}  -> RV64A; AMOOR_D{}   -> RV64A; AMOMIN_D{}  -> RV64A
  AMOMAX_D{}  -> RV64A; AMOMINU_D{} -> RV64A; AMOMAXU_D{} -> RV64A
  -- RV64F
  FLW{} -> RV64F; FSW{} -> RV64F
  FMADD_S{} -> RV64F; FMSUB_S{} -> RV64F; FNMADD_S{} -> RV64F; FNMSUB_S{} -> RV64F
  FADD_S{} -> RV64F; FSUB_S{} -> RV64F; FMUL_S{} -> RV64F; FDIV_S{} -> RV64F
  FSQRT_S{} -> RV64F; FSGNJ_S{} -> RV64F; FSGNJN_S{} -> RV64F; FSGNJX_S{} -> RV64F
  FMIN_S{} -> RV64F; FMAX_S{} -> RV64F
  FCVT_W_S{} -> RV64F; FCVT_WU_S{} -> RV64F; FCVT_L_S{} -> RV64F; FCVT_LU_S{} -> RV64F
  FCVT_S_W{} -> RV64F; FCVT_S_WU{} -> RV64F; FCVT_S_L{} -> RV64F; FCVT_S_LU{} -> RV64F
  FMV_X_W{} -> RV64F; FMV_W_X{} -> RV64F
  FEQ_S{} -> RV64F; FLT_S{} -> RV64F; FLE_S{} -> RV64F; FCLASS_S{} -> RV64F
  -- RV64D
  FLD{} -> RV64D; FSD{} -> RV64D
  FMADD_D{} -> RV64D; FMSUB_D{} -> RV64D; FNMADD_D{} -> RV64D; FNMSUB_D{} -> RV64D
  FADD_D{} -> RV64D; FSUB_D{} -> RV64D; FMUL_D{} -> RV64D; FDIV_D{} -> RV64D
  FSQRT_D{} -> RV64D; FSGNJ_D{} -> RV64D; FSGNJN_D{} -> RV64D; FSGNJX_D{} -> RV64D
  FMIN_D{} -> RV64D; FMAX_D{} -> RV64D
  FCVT_S_D{} -> RV64D; FCVT_D_S{} -> RV64D
  FCVT_W_D{} -> RV64D; FCVT_WU_D{} -> RV64D; FCVT_L_D{} -> RV64D; FCVT_LU_D{} -> RV64D
  FCVT_D_W{} -> RV64D; FCVT_D_WU{} -> RV64D; FCVT_D_L{} -> RV64D; FCVT_D_LU{} -> RV64D
  FMV_X_D{} -> RV64D; FMV_D_X{} -> RV64D
  FEQ_D{} -> RV64D; FLT_D{} -> RV64D; FLE_D{} -> RV64D; FCLASS_D{} -> RV64D
  _        -> RV64I

instrFormat :: Instruction -> InstrFormat
instrFormat = \case
  ADD{} -> RFormat; SUB{}  -> RFormat; ADDW{} -> RFormat; SUBW{} -> RFormat
  AND{} -> RFormat; OR{}   -> RFormat; XOR{}  -> RFormat
  SLL{} -> RFormat; SRL{}  -> RFormat; SRA{}  -> RFormat
  SLLW{} -> RFormat; SRLW{} -> RFormat; SRAW{} -> RFormat
  SLT{} -> RFormat; SLTU{} -> RFormat
  MUL{}  -> RFormat; MULH{}  -> RFormat; MULHSU{} -> RFormat; MULHU{} -> RFormat
  DIV{}  -> RFormat; DIVU{}  -> RFormat; REM{}    -> RFormat; REMU{}  -> RFormat
  MULW{} -> RFormat; DIVW{}  -> RFormat; DIVUW{}  -> RFormat; REMW{}  -> RFormat
  REMUW{} -> RFormat
  ADDI{} -> IFormat; ADDIW{} -> IFormat; SLLI{} -> IFormat; SRLI{} -> IFormat
  SRAI{} -> IFormat; SLLIW{} -> IFormat; SRLIW{} -> IFormat; SRAIW{} -> IFormat
  SLTI{} -> IFormat; SLTIU{} -> IFormat; ANDI{} -> IFormat; ORI{}  -> IFormat
  XORI{} -> IFormat; LB{} -> IFormat; LH{} -> IFormat; LW{} -> IFormat
  LD{} -> IFormat; LBU{} -> IFormat; LHU{} -> IFormat; LWU{} -> IFormat
  JALR{} -> IFormat; CSRRW{} -> IFormat; CSRRS{} -> IFormat; CSRRC{} -> IFormat
  CSRRWI{} -> IFormat; CSRRSI{} -> IFormat; CSRRCI{} -> IFormat
  ECALL -> IFormat; EBREAK -> IFormat; FENCE{} -> IFormat; FENCE_I -> IFormat
  MRET -> RFormat; SRET -> RFormat; WFI -> RFormat; SFENCE_VMA{} -> RFormat
  LR_W{} -> RFormat; LR_D{} -> RFormat
  SC_W{} -> RFormat; SC_D{} -> RFormat
  AMOSWAP_W{} -> RFormat; AMOADD_W{}  -> RFormat; AMOXOR_W{}  -> RFormat
  AMOAND_W{}  -> RFormat; AMOOR_W{}   -> RFormat; AMOMIN_W{}  -> RFormat
  AMOMAX_W{}  -> RFormat; AMOMINU_W{} -> RFormat; AMOMAXU_W{} -> RFormat
  AMOSWAP_D{} -> RFormat; AMOADD_D{}  -> RFormat; AMOXOR_D{}  -> RFormat
  AMOAND_D{}  -> RFormat; AMOOR_D{}   -> RFormat; AMOMIN_D{}  -> RFormat
  AMOMAX_D{}  -> RFormat; AMOMINU_D{} -> RFormat; AMOMAXU_D{} -> RFormat
  SB{} -> SFormat; SH{} -> SFormat; SW{} -> SFormat; SD{} -> SFormat
  BEQ{} -> BFormat; BNE{} -> BFormat; BLT{} -> BFormat; BGE{} -> BFormat
  BLTU{} -> BFormat; BGEU{} -> BFormat
  LUI{} -> UFormat; AUIPC{} -> UFormat
  JAL{} -> JFormat
  -- RV64F
  FLW{} -> IFormat; FSW{} -> SFormat
  FMADD_S{} -> RFormat; FMSUB_S{} -> RFormat; FNMADD_S{} -> RFormat; FNMSUB_S{} -> RFormat
  FADD_S{} -> RFormat; FSUB_S{} -> RFormat; FMUL_S{} -> RFormat; FDIV_S{} -> RFormat
  FSQRT_S{} -> RFormat; FSGNJ_S{} -> RFormat; FSGNJN_S{} -> RFormat; FSGNJX_S{} -> RFormat
  FMIN_S{} -> RFormat; FMAX_S{} -> RFormat
  FCVT_W_S{} -> IFormat; FCVT_WU_S{} -> IFormat; FCVT_L_S{} -> IFormat; FCVT_LU_S{} -> IFormat
  FCVT_S_W{} -> RFormat; FCVT_S_WU{} -> RFormat; FCVT_S_L{} -> RFormat; FCVT_S_LU{} -> RFormat
  FMV_X_W{} -> RFormat; FMV_W_X{} -> RFormat
  FEQ_S{} -> RFormat; FLT_S{} -> RFormat; FLE_S{} -> RFormat; FCLASS_S{} -> RFormat
  -- RV64D
  FLD{} -> IFormat; FSD{} -> SFormat
  FMADD_D{} -> RFormat; FMSUB_D{} -> RFormat; FNMADD_D{} -> RFormat; FNMSUB_D{} -> RFormat
  FADD_D{} -> RFormat; FSUB_D{} -> RFormat; FMUL_D{} -> RFormat; FDIV_D{} -> RFormat
  FSQRT_D{} -> RFormat; FSGNJ_D{} -> RFormat; FSGNJN_D{} -> RFormat; FSGNJX_D{} -> RFormat
  FMIN_D{} -> RFormat; FMAX_D{} -> RFormat
  FCVT_S_D{} -> RFormat; FCVT_D_S{} -> RFormat
  FCVT_W_D{} -> IFormat; FCVT_WU_D{} -> IFormat; FCVT_L_D{} -> IFormat; FCVT_LU_D{} -> IFormat
  FCVT_D_W{} -> RFormat; FCVT_D_WU{} -> RFormat; FCVT_D_L{} -> RFormat; FCVT_D_LU{} -> RFormat
  FMV_X_D{} -> RFormat; FMV_D_X{} -> RFormat
  FEQ_D{} -> RFormat; FLT_D{} -> RFormat; FLE_D{} -> RFormat; FCLASS_D{} -> RFormat

isRV64I, isRV64M, isPrivileged :: Instruction -> Bool
isRV64I      i = instrExtension i == RV64I
isRV64M      i = instrExtension i == RV64M
isPrivileged i = instrExtension i == RVPriv

requiresExtensions :: Instruction -> [Extension]
requiresExtensions i = case instrExtension i of
  RV64A -> [RV64A, RV64I]
  RV64F -> [RV64F, RV64I]
  RV64D -> [RV64D, RV64F, RV64I]
  RV64C -> [RV64C, RV64I]
  e     -> [e]
