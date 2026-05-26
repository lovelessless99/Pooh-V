module Test.CoSim.Spike (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import CoSim.Spike
import CoSim.Types    (lePC, leRawInstr, leHartID)
import Data.Either    (isLeft)
import Data.Text      (pack)

tests :: TestTree
tests = testGroup "CoSim.Spike"
  [ testCase "parseSpikeLogLine parses valid line" $
      let line = "core   0: 0x0000000080000000 (0x00000093) addi zero, zero, 0"
      in  case parseSpikeLogLine line of
            Right entry -> do
              lePC entry     @?= 0x80000000
              leRawInstr entry @?= 0x00000093
              leHartID entry @?= 0
            Left err -> assertFailure ("parse failed: " <> show err)
  , testCase "parseSpikeLogLine rejects garbage" $
      isLeft (parseSpikeLogLine "not a spike log line") @?= True
  , testCase "parseSpikeLog handles multiple lines" $ do
      let logText = unlines
            [ "core   0: 0x0000000080000000 (0x00000093) addi zero, zero, 0"
            , "core   0: 0x0000000080000004 (0x00100093) addi ra, zero, 1"
            ]
      case parseSpikeLog (pack logText) of
        Right entries -> length entries @?= 2
        Left err      -> assertFailure ("parse failed: " <> show err)
  ]
