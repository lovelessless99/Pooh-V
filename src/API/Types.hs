module API.Types
  ( GenerateRequest(..)
  , GenerateResponse(..)
  , CoverageResponse(..)
  , BanditResponse(..)
  , BinInfo(..)
  , ScenarioInfo(..)
  , ScenarioRunResponse(..)
  , ServerState(..)
  , newServerState
  ) where

import Coverage.Accumulator  (CoverageAccumulator, newAccumulator)
import Coverage.Bandit       (BanditState, initBandit)
import Coverage.Types        (allCoverageBins)
import Generator.Types       (defaultConfig, GeneratorConfig)
import Data.Text             (Text)
import Data.Aeson            (ToJSON(..), FromJSON(..), genericToJSON, genericParseJSON,
                              genericToEncoding, defaultOptions, Options(..))
import GHC.Generics          (Generic)
import Control.Concurrent.STM (TVar, newTVarIO)

data GenerateRequest = GenerateRequest
  { grExtensions :: [Text]
  , grCount      :: Int
  , grMode       :: Text
  , grLengthMin  :: Int
  , grLengthMax  :: Int
  } deriving (Show, Eq, Generic)

data GenerateResponse = GenerateResponse
  { grSeqs     :: [[Text]]
  , grCoverage :: CoverageResponse
  } deriving (Show, Eq, Generic)

data CoverageResponse = CoverageResponse
  { crHit     :: Int
  , crTotal   :: Int
  , crPct     :: Double
  , crMissing :: [Text]
  } deriving (Show, Eq, Generic)

data BinInfo = BinInfo
  { biName     :: Text
  , biAlpha    :: Double
  , biBeta     :: Double
  , biPriority :: Double
  } deriving (Show, Eq, Generic)

data BanditResponse = BanditResponse
  { brBins :: [BinInfo]
  } deriving (Show, Eq, Generic)

data ScenarioInfo = ScenarioInfo
  { siName        :: Text
  , siTags        :: [Text]
  , siExtensions  :: [Text]
  , siDescription :: Text
  } deriving (Show, Eq, Generic)

data ScenarioRunResponse = ScenarioRunResponse
  { srSequence     :: [Text]
  , srCoverageHits :: [Text]
  } deriving (Show, Eq, Generic)

-- Strip prefix for JSON field names
mkOpts :: String -> Options
mkOpts p = defaultOptions { fieldLabelModifier = \s -> drop (length p) s }

instance ToJSON   GenerateRequest    where
  toJSON     = genericToJSON     (mkOpts "gr")
  toEncoding = genericToEncoding (mkOpts "gr")
instance FromJSON GenerateRequest    where parseJSON = genericParseJSON (mkOpts "gr")

instance ToJSON   GenerateResponse   where
  toJSON     = genericToJSON     (mkOpts "gr")
  toEncoding = genericToEncoding (mkOpts "gr")
instance FromJSON GenerateResponse   where parseJSON = genericParseJSON (mkOpts "gr")

instance ToJSON   CoverageResponse   where
  toJSON     = genericToJSON     (mkOpts "cr")
  toEncoding = genericToEncoding (mkOpts "cr")
instance FromJSON CoverageResponse   where parseJSON = genericParseJSON (mkOpts "cr")

instance ToJSON   BinInfo            where
  toJSON     = genericToJSON     (mkOpts "bi")
  toEncoding = genericToEncoding (mkOpts "bi")
instance FromJSON BinInfo            where parseJSON = genericParseJSON (mkOpts "bi")

instance ToJSON   BanditResponse     where
  toJSON     = genericToJSON     (mkOpts "br")
  toEncoding = genericToEncoding (mkOpts "br")
instance FromJSON BanditResponse     where parseJSON = genericParseJSON (mkOpts "br")

instance ToJSON   ScenarioInfo       where
  toJSON     = genericToJSON     (mkOpts "si")
  toEncoding = genericToEncoding (mkOpts "si")
instance FromJSON ScenarioInfo       where parseJSON = genericParseJSON (mkOpts "si")

instance ToJSON   ScenarioRunResponse where
  toJSON     = genericToJSON     (mkOpts "sr")
  toEncoding = genericToEncoding (mkOpts "sr")
instance FromJSON ScenarioRunResponse where parseJSON = genericParseJSON (mkOpts "sr")

data ServerState = ServerState
  { ssAccumulator :: CoverageAccumulator
  , ssBandit      :: TVar BanditState
  , ssConfig      :: GeneratorConfig
  }

newServerState :: IO ServerState
newServerState = ServerState
  <$> newAccumulator
  <*> newTVarIO (initBandit allCoverageBins)
  <*> pure defaultConfig
