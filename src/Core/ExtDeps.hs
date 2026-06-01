module Core.ExtDeps
  ( directDeps
  , allDepsOf
  , resolveExtensions
  ) where

import Core.Instruction (Extension(..))
import qualified Data.Set as Set

-- | Direct (one-level) dependencies of each extension.
directDeps :: Extension -> [Extension]
directDeps RV64I  = []
directDeps RV64M  = [RV64I]
directDeps RV64A  = [RV64I]
directDeps RV64F  = [RV64I]
directDeps RV64D  = [RV64F, RV64I]
directDeps RV64C  = [RV64I]
directDeps RVPriv = [RV64I]

-- | Transitive closure of dependencies starting from a set of extensions.
-- Returns the input set union all transitive dependencies.
allDepsOf :: Set.Set Extension -> Set.Set Extension
allDepsOf initial = go initial initial
  where
    go seen frontier
      | Set.null frontier = seen
      | otherwise =
          let newDeps = Set.fromList
                [ dep
                | ext <- Set.toList frontier
                , dep <- directDeps ext
                , dep `Set.notMember` seen
                ]
          in go (Set.union seen newDeps) newDeps

-- | Resolve an extension set to include all transitive dependencies.
resolveExtensions :: Set.Set Extension -> Set.Set Extension
resolveExtensions = allDepsOf
