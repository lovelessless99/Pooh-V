{-# LANGUAGE DataKinds #-}
module API.Server
  ( RigAPI
  , rigAPI
  , server
  , handleGenerate
  , handleGetCoverage
  , handleResetCoverage
  , handleGetBandit
  , handleGetScenarios
  , handleRunScenario
  , handleStream
  ) where

import API.Types
import Coverage.Accumulator  (snapshotCoverage, recordCoverage, covTVar)
import Coverage.Analysis     (CoverageSummary(..))
import Coverage.Bandit       (BanditState(..), BetaParams(..), updateBandit)
import Coverage.Classify     (classifySequence)
import Generator.Types       (GeneratorConfig(..))
import Generator.Random      (generateSequence)
import Scenario.Registry     (allScenarios, findByName)
import Scenario.Types        (ScenarioSpec(..))
import Data.Text             (Text, pack)
import Data.Map.Strict       (toAscList)
import qualified Data.Map.Strict as Map
import Control.Concurrent.STM (atomically, readTVar, readTVarIO, modifyTVar', retry)
import Control.Monad.IO.Class (liftIO)
import Network.Wai.EventSource  (ServerEvent(..), eventSourceAppIO)
import Data.ByteString.Builder  (byteString, lazyByteString)
import Data.Aeson               (encode)
import Data.IORef               (newIORef, readIORef, writeIORef)
import Servant

-- ── API type ──────────────────────────────────────────────────────────────

type RigAPI =
       "generate"  :> ReqBody '[JSON] GenerateRequest  :> Post '[JSON] GenerateResponse
  :<|> "coverage"  :> Get '[JSON] CoverageResponse
  :<|> "coverage"  :> "reset" :> Post '[JSON] NoContent
  :<|> "bandit"    :> Get '[JSON] BanditResponse
  :<|> "scenarios" :> Get '[JSON] [ScenarioInfo]
  :<|> "scenarios" :> Capture "name" Text :> "run" :> Post '[JSON] ScenarioRunResponse
  :<|> "stream"    :> Raw

rigAPI :: Proxy RigAPI
rigAPI = Proxy

-- ── Server ────────────────────────────────────────────────────────────────

server :: ServerState -> Server RigAPI
server state =
       handleGenerate      state
  :<|> handleGetCoverage   state
  :<|> handleResetCoverage state
  :<|> handleGetBandit     state
  :<|> handleGetScenarios
  :<|> handleRunScenario   state
  :<|> handleStream        state

-- ── Handlers ─────────────────────────────────────────────────────────────

handleGenerate :: ServerState -> GenerateRequest -> Handler GenerateResponse
handleGenerate state req = liftIO $ do
  let cfg = (ssConfig state)
        { gcMinLength = grLengthMin req
        , gcMaxLength = grLengthMax req
        }
  seqs <- mapM (\_ -> generateSequence cfg) [1 .. grCount req :: Int]
  let allBins = concatMap classifySequence seqs
  atomically $ recordCoverage (ssAccumulator state) allBins
  atomically $ modifyTVar' (ssBandit state) (\b -> updateBandit b allBins)
  snap <- snapshotCoverage (ssAccumulator state)
  atomically $ modifyTVar' (ssGenCounter state) (+1)
  return GenerateResponse
    { grSeqs     = map (map (pack . show)) seqs
    , grCoverage = toCoverageResponse snap
    }

handleGetCoverage :: ServerState -> Handler CoverageResponse
handleGetCoverage state = liftIO $ do
  snap <- snapshotCoverage (ssAccumulator state)
  return (toCoverageResponse snap)

handleResetCoverage :: ServerState -> Handler NoContent
handleResetCoverage state = liftIO $ do
  atomically $ modifyTVar' (covTVar (ssAccumulator state)) (const Map.empty)
  return NoContent

handleGetBandit :: ServerState -> Handler BanditResponse
handleGetBandit state = liftIO $ toBanditResponse <$> readTVarIO (ssBandit state)

toBanditResponse :: BanditState -> BanditResponse
toBanditResponse bs = BanditResponse { brBins = map toBinInfo (toAscList (bsParams bs)) }
  where
    toBinInfo (bin, BetaParams a b) = BinInfo
      { biName     = pack (show bin)
      , biAlpha    = a
      , biBeta     = b
      , biPriority = a / (a + b)
      }

handleGetScenarios :: Handler [ScenarioInfo]
handleGetScenarios = return (map toScenarioInfo allScenarios)
  where
    toScenarioInfo s = ScenarioInfo
      { siName        = sName s
      , siTags        = map (pack . show) (sTags s)
      , siExtensions  = map (pack . show) (sExtensions s)
      , siDescription = sDescription s
      }

handleRunScenario :: ServerState -> Text -> Handler ScenarioRunResponse
handleRunScenario state name = case findByName name of
  Nothing    -> throwError err404
  Just _spec -> liftIO $ do
    seq_ <- generateSequence (ssConfig state)
    let bins = classifySequence seq_
    return ScenarioRunResponse
      { srSequence     = map (pack . show) seq_
      , srCoverageHits = map (pack . show) bins
      }

handleStream :: ServerState -> Tagged Handler Application
handleStream state = Tagged $ \req sendResponse -> do
  lastRef <- newIORef =<< readTVarIO (ssGenCounter state)
  eventSourceAppIO (nextEvent lastRef) req sendResponse
  where
    nextEvent lastRef = do
      last_ <- readIORef lastRef
      newCount <- atomically $ do
        c <- readTVar (ssGenCounter state)
        if c > last_ then return c else retry
      writeIORef lastRef newCount
      snap <- snapshotCoverage (ssAccumulator state)
      bs   <- readTVarIO (ssBandit state)
      let evt = SSEEvent (toCoverageResponse snap) (toBanditResponse bs)
      return $ ServerEvent
        { eventName = Just (byteString "update")
        , eventId   = Nothing
        , eventData = [lazyByteString (encode evt)]
        }

-- ── Helper ────────────────────────────────────────────────────────────────

toCoverageResponse :: CoverageSummary -> CoverageResponse
toCoverageResponse s = CoverageResponse
  { crHit     = hitBins s
  , crTotal   = totalBins s
  , crPct     = coveragePct s
  , crMissing = map (pack . show) (take 20 (missingBins s))
  }
