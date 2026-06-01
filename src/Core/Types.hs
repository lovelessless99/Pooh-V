module Core.Types
  ( Register(..), FPRegister(..), CSRAddr(..)
  , Imm12(..), Imm13(..), Imm20(..), Imm21(..), Imm6(..), Imm9(..), Imm10(..)
  , UImm5(..), UImm6(..), UImm7(..), UImm8(..), UImm9(..), UImm10(..)
  , AqRl(..), RoundingMode(..), FenceMode(..)
  , PrivilegeLevel(..)
  -- Integer register aliases (ABI names)
  , x0, ra, sp, gp, tp, t0, t1, t2, fp, s1
  , a0, a1, a2, a3, a4, a5, a6, a7
  , s2, s3, s4, s5, s6, s7, s8, s9, s10, s11
  , t3, t4, t5, t6
  , x1, x2, x3, x4, x5, x6, x7, x8, x9, x10
  , x11, x12, x13, x14, x15, x16, x17, x18, x19, x20
  , x21, x22, x23, x24, x25, x26, x27, x28, x29, x30, x31
  -- FP register aliases
  , ft0, ft1, ft2, ft3, ft4, ft5, ft6, ft7
  , fs0, fs1
  , fa0, fa1, fa2, fa3, fa4, fa5, fa6, fa7
  , fs2, fs3, fs4, fs5, fs6, fs7, fs8, fs9, fs10, fs11
  , ft8, ft9, ft10, ft11
  ) where

import Data.Word  (Word8, Word16)
import Data.Int   (Int8, Int16, Int32)
import GHC.Generics (Generic)

newtype Register   = Register   { unReg  :: Word8  }
  deriving (Show, Eq, Ord, Generic)
newtype FPRegister = FPRegister { unFReg :: Word8  }
  deriving (Show, Eq, Ord, Generic)
newtype CSRAddr    = CSRAddr    { unCSR  :: Word16 }
  deriving (Show, Eq, Ord, Generic)

newtype Imm12  = Imm12  { unImm12  :: Int16 } deriving (Show, Eq, Ord, Generic)
newtype Imm13  = Imm13  { unImm13  :: Int16 } deriving (Show, Eq, Ord, Generic)
newtype Imm20  = Imm20  { unImm20  :: Int32 } deriving (Show, Eq, Ord, Generic)
newtype Imm21  = Imm21  { unImm21  :: Int32 } deriving (Show, Eq, Ord, Generic)
newtype Imm6   = Imm6   { unImm6   :: Int8  } deriving (Show, Eq, Ord, Generic)
newtype UImm5  = UImm5  { unUImm5  :: Word8 } deriving (Show, Eq, Ord, Generic)
newtype UImm6  = UImm6  { unUImm6  :: Word8 } deriving (Show, Eq, Ord, Generic)

-- New types for RV64C compressed immediates
newtype UImm7  = UImm7  { unUImm7  :: Word8  } deriving (Show, Eq, Ord, Generic)
newtype UImm8  = UImm8  { unUImm8  :: Word8  } deriving (Show, Eq, Ord, Generic)
newtype UImm9  = UImm9  { unUImm9  :: Word16 } deriving (Show, Eq, Ord, Generic)
newtype UImm10 = UImm10 { unUImm10 :: Word16 } deriving (Show, Eq, Ord, Generic)
newtype Imm9   = Imm9   { unImm9   :: Int16  } deriving (Show, Eq, Ord, Generic)
newtype Imm10  = Imm10  { unImm10  :: Int16  } deriving (Show, Eq, Ord, Generic)

data AqRl
  = AqRlNone
  | AqRlRelease
  | AqRlAcquire
  | AqRlAcqRel
  deriving (Show, Eq, Ord, Enum, Bounded, Generic)

data RoundingMode = RNE | RTZ | RDN | RUP | RMM | DYN
  deriving (Show, Eq, Ord, Enum, Bounded, Generic)

-- Ord is Bool-lexicographic (fenceI > fenceO > fenceR > fenceW), not the
-- 4-bit numeric encoding. Use Core.Encode.encodeFenceMode for the bit value.
data FenceMode = FenceMode
  { fenceI :: Bool
  , fenceO :: Bool
  , fenceR :: Bool
  , fenceW :: Bool
  } deriving (Show, Eq, Ord, Generic)

data PrivilegeLevel = User | Supervisor | Machine
  deriving (Show, Eq, Ord, Enum, Bounded, Generic)

x0, ra, sp, gp, tp, t0, t1, t2, fp, s1 :: Register
a0, a1, a2, a3, a4, a5, a6, a7         :: Register
s2, s3, s4, s5, s6, s7, s8, s9, s10, s11 :: Register
t3, t4, t5, t6                          :: Register
x0  = Register  0;  ra  = Register  1;  sp  = Register  2
gp  = Register  3;  tp  = Register  4;  t0  = Register  5
t1  = Register  6;  t2  = Register  7;  fp  = Register  8
s1  = Register  9;  a0  = Register 10;  a1  = Register 11
a2  = Register 12;  a3  = Register 13;  a4  = Register 14
a5  = Register 15;  a6  = Register 16;  a7  = Register 17
s2  = Register 18;  s3  = Register 19;  s4  = Register 20
s5  = Register 21;  s6  = Register 22;  s7  = Register 23
s8  = Register 24;  s9  = Register 25;  s10 = Register 26
s11 = Register 27;  t3  = Register 28;  t4  = Register 29
t5  = Register 30;  t6  = Register 31

-- Numeric aliases x1..x31 (same physical registers, different names)
x1, x2, x3, x4, x5, x6, x7, x8, x9, x10 :: Register
x11, x12, x13, x14, x15, x16, x17, x18, x19, x20 :: Register
x21, x22, x23, x24, x25, x26, x27, x28, x29, x30, x31 :: Register
x1  = Register  1;  x2  = Register  2;  x3  = Register  3
x4  = Register  4;  x5  = Register  5;  x6  = Register  6
x7  = Register  7;  x8  = Register  8;  x9  = Register  9
x10 = Register 10;  x11 = Register 11;  x12 = Register 12
x13 = Register 13;  x14 = Register 14;  x15 = Register 15
x16 = Register 16;  x17 = Register 17;  x18 = Register 18
x19 = Register 19;  x20 = Register 20;  x21 = Register 21
x22 = Register 22;  x23 = Register 23;  x24 = Register 24
x25 = Register 25;  x26 = Register 26;  x27 = Register 27
x28 = Register 28;  x29 = Register 29;  x30 = Register 30
x31 = Register 31

-- FP register aliases (RISC-V ABI names)
ft0, ft1, ft2, ft3, ft4, ft5, ft6, ft7 :: FPRegister
fs0, fs1                                :: FPRegister
fa0, fa1, fa2, fa3, fa4, fa5, fa6, fa7 :: FPRegister
fs2, fs3, fs4, fs5, fs6, fs7, fs8, fs9, fs10, fs11 :: FPRegister
ft8, ft9, ft10, ft11                    :: FPRegister
ft0  = FPRegister  0; ft1  = FPRegister  1; ft2  = FPRegister  2
ft3  = FPRegister  3; ft4  = FPRegister  4; ft5  = FPRegister  5
ft6  = FPRegister  6; ft7  = FPRegister  7; fs0  = FPRegister  8
fs1  = FPRegister  9; fa0  = FPRegister 10; fa1  = FPRegister 11
fa2  = FPRegister 12; fa3  = FPRegister 13; fa4  = FPRegister 14
fa5  = FPRegister 15; fa6  = FPRegister 16; fa7  = FPRegister 17
fs2  = FPRegister 18; fs3  = FPRegister 19; fs4  = FPRegister 20
fs5  = FPRegister 21; fs6  = FPRegister 22; fs7  = FPRegister 23
fs8  = FPRegister 24; fs9  = FPRegister 25; fs10 = FPRegister 26
fs11 = FPRegister 27; ft8  = FPRegister 28; ft9  = FPRegister 29
ft10 = FPRegister 30; ft11 = FPRegister 31
