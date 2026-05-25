module Constraint.Combinators
  ( cAnd, cOr, cNot, cImplies
  , withWeight
  , addConstraint, removeConstraint, mergeConstraints
  ) where

import Constraint.Types
import Data.SBV       (sNot, (.&&), (.||))
import Data.Text      (Text, pack)

cAnd :: ConstraintDef -> ConstraintDef -> ConstraintDef
cAnd a b = ConstraintDef
  { cname        = cname a <> " && " <> cname b
  , ctags        = ctags a <> ctags b
  , cdescription = cdescription a <> " AND " <> cdescription b
  , cextensions  = cextensions a <> cextensions b
  , cpredicate   = \sym -> cpredicate a sym .&& cpredicate b sym
  }

cOr :: ConstraintDef -> ConstraintDef -> ConstraintDef
cOr a b = ConstraintDef
  { cname        = cname a <> " || " <> cname b
  , ctags        = ctags a <> ctags b
  , cdescription = cdescription a <> " OR " <> cdescription b
  , cextensions  = cextensions a <> cextensions b
  , cpredicate   = \sym -> cpredicate a sym .|| cpredicate b sym
  }

cNot :: ConstraintDef -> ConstraintDef
cNot c = c
  { cname      = "not (" <> cname c <> ")"
  , cpredicate = sNot . cpredicate c
  }

cImplies :: ConstraintDef -> ConstraintDef -> ConstraintDef
cImplies ante conseq = ConstraintDef
  { cname        = cname ante <> " => " <> cname conseq
  , ctags        = ctags ante <> ctags conseq
  , cdescription = cname ante <> " implies " <> cname conseq
  , cextensions  = cextensions ante <> cextensions conseq
  , cpredicate   = \sym ->
      sNot (cpredicate ante sym) .|| cpredicate conseq sym
  }

-- Weight is stored in the name as metadata for the optimizer.
-- It does not affect the solver — it guides the random generator.
withWeight :: Double -> ConstraintDef -> ConstraintDef
withWeight w c = c { cname = cname c <> " [w=" <> pack (show w) <> "]" }

removeConstraint :: Text -> ConstraintSet -> ConstraintSet
removeConstraint name (ConstraintSet cs) =
  ConstraintSet (filter (\c -> cname c /= name) cs)

mergeConstraints :: ConstraintSet -> ConstraintSet -> ConstraintSet
mergeConstraints (ConstraintSet a) (ConstraintSet b) = ConstraintSet (a <> b)
