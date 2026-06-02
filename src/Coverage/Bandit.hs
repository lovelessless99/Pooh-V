module Coverage.Bandit
  ( BanditState(..)
  , BetaParams(..)
  , initBandit
  , sampleTarget
  , updateBandit
  , markInfeasible
  ) where

import Coverage.Types         (CoverageBin)
import Data.List              (maximumBy)
import Data.Ord               (comparing)
import Data.Set               (Set)
import qualified Data.Map.Strict as Map
import qualified Data.Set        as Set
import System.Random.MWC                   (createSystemRandom)
import System.Random.MWC.Distributions     (beta)

data BetaParams = BetaParams
  { bpAlpha :: Double
  , bpBeta  :: Double
  } deriving (Show, Eq)

data BanditState = BanditState
  { bsParams     :: Map.Map CoverageBin BetaParams
  , bsInfeasible :: Set CoverageBin
  }

-- | Initialise with Beta(1,1) for every bin.
initBandit :: [CoverageBin] -> BanditState
initBandit bins = BanditState
  { bsParams     = Map.fromList [(b, BetaParams 1.0 1.0) | b <- bins]
  , bsInfeasible = Set.empty
  }

-- | Sample one value from each eligible bin's Beta distribution; return the
-- bin with the highest sample. Eligible = not in bsInfeasible.
sampleTarget :: BanditState -> IO CoverageBin
sampleTarget BanditState{bsParams, bsInfeasible} = do
  let eligible = [ (b, p)
                 | (b, p) <- Map.toList bsParams
                 , not (Set.member b bsInfeasible) ]
  case eligible of
    []  -> error "sampleTarget: no eligible bins (all marked infeasible)"
    [(b, _)] -> return b
    _   -> do
      gen     <- createSystemRandom
      samples <- mapM (\(b, BetaParams a bv) -> do
                    s <- beta a bv gen
                    return (s, b)) eligible
      return $ snd (maximumBy (comparing fst) samples)

-- | Update α/β after a generation round.
-- Hit bins: α += 1.  Miss bins (eligible but not hit): β += 1.
updateBandit :: BanditState -> [CoverageBin] -> BanditState
updateBandit bs hits =
  let hitSet = Set.fromList hits
      update b p@(BetaParams a bv)
        | Set.member b hitSet              = BetaParams (a + 1) bv
        | Set.member b (bsInfeasible bs)   = p
        | otherwise                        = BetaParams a (bv + 1)
  in  bs { bsParams = Map.mapWithKey update (bsParams bs) }

-- | Permanently exclude a bin from sampling (e.g. UNSAT from Z3).
markInfeasible :: BanditState -> CoverageBin -> BanditState
markInfeasible bs bin = bs { bsInfeasible = Set.insert bin (bsInfeasible bs) }
