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
  deriving (Show, Eq, Ord, Generic)

instrExtension :: Instruction -> Extension
instrExtension instr = case instr of
  MUL{}    -> RV64M; MULH{}   -> RV64M; MULHSU{} -> RV64M; MULHU{}  -> RV64M
  DIV{}    -> RV64M; DIVU{}   -> RV64M; REM{}     -> RV64M; REMU{}   -> RV64M
  MULW{}   -> RV64M; DIVW{}   -> RV64M; DIVUW{}   -> RV64M; REMW{}   -> RV64M
  REMUW{}  -> RV64M
  MRET     -> RVPriv; SRET -> RVPriv; WFI -> RVPriv; SFENCE_VMA{} -> RVPriv
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
  SB{} -> SFormat; SH{} -> SFormat; SW{} -> SFormat; SD{} -> SFormat
  BEQ{} -> BFormat; BNE{} -> BFormat; BLT{} -> BFormat; BGE{} -> BFormat
  BLTU{} -> BFormat; BGEU{} -> BFormat
  LUI{} -> UFormat; AUIPC{} -> UFormat
  JAL{} -> JFormat

isRV64I, isRV64M, isPrivileged :: Instruction -> Bool
isRV64I      i = instrExtension i == RV64I
isRV64M      i = instrExtension i == RV64M
isPrivileged i = instrExtension i == RVPriv

requiresExtensions :: Instruction -> [Extension]
requiresExtensions i = [instrExtension i]
