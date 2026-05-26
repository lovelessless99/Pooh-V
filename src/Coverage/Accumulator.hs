module Coverage.Accumulator
  ( CoverageAccumulator(..)
  , newAccumulator
  , recordCoverage
  , snapshotCoverage
  ) where

import Coverage.Types
import Coverage.Analysis (CoverageSummary, coverageSummary)
import Control.Concurrent.STM
import qualified Data.Map.Strict as Map

data CoverageAccumulator = CoverageAccumulator
  { covTVar :: TVar CoverageMap
  }

newAccumulator :: IO CoverageAccumulator
newAccumulator = CoverageAccumulator <$> newTVarIO Map.empty

recordCoverage :: CoverageAccumulator -> [CoverageBin] -> STM ()
recordCoverage acc bins =
  modifyTVar' (covTVar acc) (applyHits bins)
  where
    applyHits bs m = foldr (\b -> Map.insertWith (+) b 1) m bs

snapshotCoverage :: CoverageAccumulator -> IO CoverageSummary
snapshotCoverage acc = do
  m <- readTVarIO (covTVar acc)
  return (coverageSummary m allOpcodeBins)
