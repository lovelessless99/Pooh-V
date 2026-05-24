module Core.CSR
  ( CSR(..)
  , csrAddr
  , CSRAccess(..)
  , csrAccessRules
  ) where

import Core.Types

data CSR
  -- Machine Info (read-only)
  = Mvendorid | Marchid | Mimpid | Mhartid
  -- Machine Trap Setup
  | Mstatus | Misa | Medeleg | Mideleg | Mie | Mtvec | Mcounteren
  -- Machine Trap Handling
  | Mscratch | Mepc | Mcause | Mtval | Mip
  -- Supervisor Trap Setup
  | Sstatus | Sedeleg | Sideleg | Sie | Stvec | Scounteren
  -- Supervisor Trap Handling
  | Sscratch | Sepc | Scause | Stval | Sip
  -- Supervisor VM
  | Satp
  -- Performance Counters (unprivileged read)
  | Cycle | Time | Instret
  -- Machine Counters
  | Mcycle | Minstret
  -- FP status
  | Fflags | Frm | Fcsr
  deriving (Show, Eq, Ord, Enum, Bounded)

csrAddr :: CSR -> CSRAddr
csrAddr = CSRAddr . \case
  Mvendorid -> 0xF11; Marchid -> 0xF12; Mimpid -> 0xF13; Mhartid -> 0xF14
  Mstatus   -> 0x300; Misa    -> 0x301; Medeleg -> 0x302; Mideleg -> 0x303
  Mie       -> 0x304; Mtvec   -> 0x305; Mcounteren -> 0x306
  Mscratch  -> 0x340; Mepc    -> 0x341; Mcause  -> 0x342; Mtval   -> 0x343
  Mip       -> 0x344
  Sstatus   -> 0x100; Sedeleg -> 0x102; Sideleg -> 0x103; Sie     -> 0x104
  Stvec     -> 0x105; Scounteren -> 0x106
  Sscratch  -> 0x140; Sepc    -> 0x141; Scause  -> 0x142; Stval   -> 0x143
  Sip       -> 0x144; Satp    -> 0x180
  Cycle     -> 0xC00; Time    -> 0xC01; Instret -> 0xC02
  Mcycle    -> 0xB00; Minstret -> 0xB02
  Fflags    -> 0x001; Frm     -> 0x002; Fcsr    -> 0x003

data CSRAccess = CSRAccess
  { readPriv  :: PrivilegeLevel
  , writePriv :: PrivilegeLevel
  , readOnly  :: Bool
  }

csrAccessRules :: CSR -> CSRAccess
csrAccessRules = \case
  Mvendorid  -> CSRAccess Machine Machine True
  Marchid    -> CSRAccess Machine Machine True
  Mimpid     -> CSRAccess Machine Machine True
  Mhartid    -> CSRAccess Machine Machine True
  Mstatus    -> CSRAccess Machine Machine False
  Misa       -> CSRAccess Machine Machine False
  Medeleg    -> CSRAccess Machine Machine False
  Mideleg    -> CSRAccess Machine Machine False
  Mie        -> CSRAccess Machine Machine False
  Mtvec      -> CSRAccess Machine Machine False
  Mcounteren -> CSRAccess Machine Machine False
  Mscratch   -> CSRAccess Machine Machine False
  Mepc       -> CSRAccess Machine Machine False
  Mcause     -> CSRAccess Machine Machine False
  Mtval      -> CSRAccess Machine Machine False
  Mip        -> CSRAccess Machine Machine False
  Sstatus    -> CSRAccess Supervisor Supervisor False
  Sedeleg    -> CSRAccess Supervisor Supervisor False
  Sideleg    -> CSRAccess Supervisor Supervisor False
  Sie        -> CSRAccess Supervisor Supervisor False
  Stvec      -> CSRAccess Supervisor Supervisor False
  Scounteren -> CSRAccess Supervisor Supervisor False
  Sscratch   -> CSRAccess Supervisor Supervisor False
  Sepc       -> CSRAccess Supervisor Supervisor False
  Scause     -> CSRAccess Supervisor Supervisor False
  Stval      -> CSRAccess Supervisor Supervisor False
  Sip        -> CSRAccess Supervisor Supervisor False
  Satp       -> CSRAccess Supervisor Supervisor False
  Cycle      -> CSRAccess User User True
  Time       -> CSRAccess User User True
  Instret    -> CSRAccess User User True
  Mcycle     -> CSRAccess Machine Machine False
  Minstret   -> CSRAccess Machine Machine False
  Fflags     -> CSRAccess User User False
  Frm        -> CSRAccess User User False
  Fcsr       -> CSRAccess User User False
