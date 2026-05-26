module Coverage.Analysis
  ( CoverageSummary(..)
  , coverageSummary
  , renderSummary
  ) where

import Coverage.Types
import qualified Data.Map.Strict as Map

data CoverageSummary = CoverageSummary
  { covMap      :: CoverageMap
  , totalBins   :: Int
  , hitBins     :: Int
  , missingBins :: [CoverageBin]
  , coveragePct :: Double
  } deriving (Show)

coverageSummary :: CoverageMap -> [CoverageBin] -> CoverageSummary
coverageSummary cmap allBins = CoverageSummary
  { covMap      = cmap
  , totalBins   = total
  , hitBins     = hits
  , missingBins = filter (\b -> Map.findWithDefault 0 b cmap == 0) allBins
  , coveragePct = if total == 0 then 0.0
                  else fromIntegral hits / fromIntegral total * 100.0
  }
  where
    total = length allBins
    hits  = length (filter (\b -> Map.findWithDefault 0 b cmap > 0) allBins)

-- Render a text coverage summary with ASCII progress bars
renderSummary :: CoverageSummary -> String
renderSummary s = unlines
  [ "Coverage: " <> show (hitBins s) <> "/" <> show (totalBins s)
    <> " bins (" <> showPct (coveragePct s) <> "%)"
  , "  " <> progressBar 40 (coveragePct s)
  , ""
  , "Top uncovered bins:"
  , unlines (map (\b -> "  x " <> showBin b) (take 10 (missingBins s)))
  ]
  where
    showPct p = show (round p :: Int)
    progressBar w pct =
      let filled = round (pct / 100.0 * fromIntegral w) :: Int
      in  "[" <> replicate filled '#' <> replicate (w - filled) '.' <> "]"
    showBin (OpcodeBin name) = show name
