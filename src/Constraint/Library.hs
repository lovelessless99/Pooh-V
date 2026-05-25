module Constraint.Library
  ( rdNotZero, rs1NotZero, rs2NotZero
  , rdNotSameAsRs1
  , alignedImm, immInRange
  , branchImmEven
  , noLoadUseHazard
  ) where

import Constraint.Types
import Data.SBV
import Data.Text (pack)

rdNotZero :: ConstraintDef
rdNotZero = ConstraintDef
  { cname        = "rd-not-zero"
  , ctags        = [Register, SafetyNet]
  , cdescription = "rd != x0; avoid writing to the zero register"
  , cextensions  = []
  , cpredicate   = \s -> symRd s ./= 0
  }

rs1NotZero :: ConstraintDef
rs1NotZero = ConstraintDef
  { cname        = "rs1-not-zero"
  , ctags        = [Register]
  , cdescription = "rs1 != x0"
  , cextensions  = []
  , cpredicate   = \s -> symRs1 s ./= 0
  }

rs2NotZero :: ConstraintDef
rs2NotZero = ConstraintDef
  { cname        = "rs2-not-zero"
  , ctags        = [Register]
  , cdescription = "rs2 != x0"
  , cextensions  = []
  , cpredicate   = \s -> symRs2 s ./= 0
  }

rdNotSameAsRs1 :: ConstraintDef
rdNotSameAsRs1 = ConstraintDef
  { cname        = "rd-not-rs1"
  , ctags        = [Register]
  , cdescription = "rd != rs1; useful for testing instruction fusion boundaries"
  , cextensions  = []
  , cpredicate   = \s -> symRd s ./= symRs1 s
  }

alignedImm :: Int -> ConstraintDef
alignedImm n = ConstraintDef
  { cname        = "aligned-imm-" <> pack (show n)
  , ctags        = [Memory, Alignment]
  , cdescription = "immediate offset must be " <> pack (show n) <> "-byte aligned"
  , cextensions  = []
  , cpredicate   = \s ->
      symImm s `sRem` literal (fromIntegral n) .== 0
  }

immInRange :: Int32 -> Int32 -> ConstraintDef
immInRange lo hi = ConstraintDef
  { cname        = "imm-in-range-[" <> pack (show lo) <> "," <> pack (show hi) <> "]"
  , ctags        = [Memory]
  , cdescription = "immediate in [" <> pack (show lo) <> ", " <> pack (show hi) <> "]"
  , cextensions  = []
  , cpredicate   = \s ->
      symImm s .>= literal lo .&& symImm s .<= literal hi
  }

branchImmEven :: ConstraintDef
branchImmEven = ConstraintDef
  { cname        = "branch-imm-even"
  , ctags        = [Branch]
  , cdescription = "branch offset must be even (2-byte aligned)"
  , cextensions  = []
  , cpredicate   = \s -> symImm s `sRem` 2 .== 0
  }

noLoadUseHazard :: ConstraintDef
noLoadUseHazard = ConstraintDef
  { cname        = "no-load-use-hazard"
  , ctags        = [Performance]
  , cdescription = "rs1 != rd within the same instruction (approx. single-instruction)"
  , cextensions  = []
  , cpredicate   = \s -> symRs1 s ./= symRd s
  }
