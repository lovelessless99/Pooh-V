module CoSim.Diff
  ( diffArchState
  , gprDiffs
  , csrDiffs
  ) where

import CoSim.Types
import Core.Types       (Register(..))
import qualified Data.Map.Strict as Map
import qualified Data.Vector as V

diffArchState :: ArchState -> ArchState -> [StateDiff]
diffArchState s1 s2 = concat
  [ [ PCDiff (asPC s1) (asPC s2) | asPC s1 /= asPC s2 ]
  , gprDiffs s1 s2
  , csrDiffs s1 s2
  , memDiffs s1 s2
  , [ PrivDiff (asPriv s1) (asPriv s2) | asPriv s1 /= asPriv s2 ]
  ]

gprDiffs :: ArchState -> ArchState -> [StateDiff]
gprDiffs s1 s2 =
  [ GPRDiff (Register (fromIntegral i)) v1 v2
  | i <- [0..31 :: Int]
  , let v1 = asGPRs s1 V.! i
        v2 = asGPRs s2 V.! i
  , v1 /= v2
  ]

csrDiffs :: ArchState -> ArchState -> [StateDiff]
csrDiffs s1 s2 =
  [ CSRDiff addr v1 v2
  | addr <- Map.keys (Map.unionWith const (asCSRs s1) (asCSRs s2))
  , let v1 = Map.findWithDefault 0 addr (asCSRs s1)
        v2 = Map.findWithDefault 0 addr (asCSRs s2)
  , v1 /= v2
  ]

memDiffs :: ArchState -> ArchState -> [StateDiff]
memDiffs s1 s2 =
  [ MemDiff addr b1 b2
  | addr <- Map.keys (Map.unionWith const (asMem s1) (asMem s2))
  , let b1 = Map.findWithDefault 0 addr (asMem s1)
        b2 = Map.findWithDefault 0 addr (asMem s2)
  , b1 /= b2
  ]
