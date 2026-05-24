module Core.Types
  ( Register(..), FPRegister(..), CSRAddr(..)
  , Imm12(..), Imm13(..), Imm20(..), Imm21(..), Imm6(..)
  , UImm5(..)
  , AqRl(..), RoundingMode(..), FenceMode(..)
  , PrivilegeLevel(..)
  -- Register aliases
  , x0, ra, sp, gp, tp, t0, t1, t2, fp, s1
  , a0, a1, a2, a3, a4, a5, a6, a7
  , s2, s3, s4, s5, s6, s7, s8, s9, s10, s11
  , t3, t4, t5, t6
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

data AqRl
  = AqRlNone
  | AqRlRelease
  | AqRlAcquire
  | AqRlAcqRel
  deriving (Show, Eq, Ord, Enum, Bounded, Generic)

data RoundingMode = RNE | RTZ | RDN | RUP | RMM | DYN
  deriving (Show, Eq, Ord, Enum, Bounded, Generic)

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
