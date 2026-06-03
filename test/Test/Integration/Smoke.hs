module Test.Integration.Smoke (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import System.Exit      (ExitCode(..))
import System.Process   (readProcess)
import System.IO.Error  (tryIOError)
import Control.Exception (SomeException, try)
import Core.Types
import Core.Instruction
import Generator.Types  (defaultConfig, GeneratorConfig(..))
import Generator.Seed   (seedFromWord64)
import Generator.Random (generateSequence)
import ELF.FlatBinary
import CoSim.Spike
import System.IO.Temp   (withSystemTempFile)

tests :: TestTree
tests = testGroup "Integration"
  [ testCase "spike is on PATH" $ do
      result <- try (readProcess "spike" ["--help"] "") :: IO (Either SomeException String)
      case result of
        Left _  -> putStrLn "SKIP: spike not on PATH"
        Right _ -> return ()

  , testCase "generate and run trivial program through Spike" $ do
      spikeExists <- checkSpikeExists
      if not spikeExists
        then putStrLn "SKIP: spike not on PATH"
        else do
          let cfg = defaultConfig { gcSeed = seedFromWord64 0xDEAD }
          seq_ <- generateSequence cfg
          let prog = TestProgram
                { tpStartup     = defaultStartup
                , tpTrapHandler = defaultTrapHandler
                , tpTestBody    = take 5 seq_ <> [ADDI x1 x0 (Imm12 1)]
                , tpExit        = defaultExit
                }
          withSystemTempFile "smoke-test-.elf" $ \path _ -> do
            writeElf prog path
            result <- runSpike defaultSpikeConfig path
            srExitCode result @?= ExitSuccess

  , testCase "10 random sequences through Spike all pass" $ do
      spikeExists <- checkSpikeExists
      if not spikeExists
        then putStrLn "SKIP: spike not on PATH"
        else do
          results <- mapM runOneSeq [0..9]
          let failures = filter (/= ExitSuccess) results
          failures @?= []
  ]

runOneSeq :: Int -> IO ExitCode
runOneSeq i = do
  let cfg = defaultConfig { gcSeed = seedFromWord64 (fromIntegral i * 1000 + 42) }
  seq_ <- generateSequence cfg
  let prog = TestProgram
        { tpStartup     = defaultStartup
        , tpTrapHandler = defaultTrapHandler
        , tpTestBody    = seq_
        , tpExit        = defaultExit
        }
  withSystemTempFile "riscv-rig-smoke-.elf" $ \path _ -> do
    writeElf prog path
    result <- runSpike defaultSpikeConfig path
    return (srExitCode result)

checkSpikeExists :: IO Bool
checkSpikeExists = do
  result <- tryIOError (readProcess "spike" ["--help"] "")
  return (either (const False) (const True) result)
