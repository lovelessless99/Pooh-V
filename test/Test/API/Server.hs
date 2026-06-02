module Test.API.Server (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import API.Types
import API.Server  (handleGenerate, handleGetCoverage, handleResetCoverage, handleGetBandit)
import Servant.Server (runHandler)
import Data.Text   (pack)
import Data.Aeson  (encode, decode)
import Control.Concurrent.STM    (readTVarIO)
import qualified Data.ByteString.Lazy.Char8 as LBS
import Data.List                 (isInfixOf)

tests :: TestTree
tests = testGroup "API.Server"
  [ testCase "GET /coverage returns valid CoverageResponse" $ do
      state <- newServerState
      result <- runHandler (handleGetCoverage state)
      case result of
        Left err  -> assertFailure (show err)
        Right resp -> crTotal resp > 0 @?= True

  , testCase "POST /coverage/reset returns NoContent" $ do
      state <- newServerState
      result <- runHandler (handleResetCoverage state)
      case result of
        Left err -> assertFailure (show err)
        Right _  -> return ()

  , testCase "POST /generate returns non-empty sequence list" $ do
      state <- newServerState
      let req = GenerateRequest
            { grExtensions = [pack "RV64I"]
            , grCount      = 2
            , grMode       = pack "random"
            , grLengthMin  = 5
            , grLengthMax  = 10
            }
      result <- runHandler (handleGenerate state req)
      case result of
        Left err  -> assertFailure (show err)
        Right resp -> null (grSeqs resp) @?= False

  , testCase "GET /bandit returns bin list" $ do
      state <- newServerState
      result <- runHandler (handleGetBandit state)
      case result of
        Left err  -> assertFailure (show err)
        Right resp -> null (brBins resp) @?= False

  , testCase "CoverageResponse JSON round-trips" $ do
      let resp = CoverageResponse 10 180 5.6 [pack "ADD", pack "SUB"]
      decode (encode resp) @?= Just resp

  , testCase "GenerateRequest JSON round-trips" $ do
      let req = GenerateRequest [pack "RV64I"] 3 (pack "random") 5 20
      decode (encode req) @?= Just req

  , testCase "handleGenerate increments ssGenCounter" $ do
      state <- newServerState
      let req = GenerateRequest
            { grExtensions = [pack "RV64I"]
            , grCount      = 1
            , grMode       = pack "random"
            , grLengthMin  = 5
            , grLengthMax  = 10
            }
      before <- readTVarIO (ssGenCounter state)
      _ <- runHandler (handleGenerate state req)
      after  <- readTVarIO (ssGenCounter state)
      after @?= before + 1

  , testCase "SSEEvent JSON encodes coverage as 'coverage' key" $ do
      let ev = SSEEvent
                (CoverageResponse 5 100 5.0 [])
                (BanditResponse [])
      assertBool "encoded JSON contains key 'Coverage'"
        ("\"Coverage\"" `isInfixOf` LBS.unpack (encode ev))
  ]
