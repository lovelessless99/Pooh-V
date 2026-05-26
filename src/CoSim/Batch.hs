module CoSim.Batch
  ( BatchConfig(..)
  , BatchResult(..)
  , defaultBatchConfig
  , runBatch
  ) where

import CoSim.Spike
import CoSim.Oracle     (CoSimOracle(..))
import ELF.FlatBinary   (TestProgram(..), writeElf, defaultStartup, defaultTrapHandler, defaultExit)
import Data.List        (foldl')
import System.Exit      (ExitCode(..))
import System.IO.Temp   (withSystemTempFile)

data BatchConfig = BatchConfig
  { bcOracles     :: [CoSimOracle]
  , bcSpikeConfig :: SpikeConfig
  } deriving (Show)

defaultBatchConfig :: BatchConfig
defaultBatchConfig = BatchConfig
  { bcOracles     = [OracleSpike "spike"]
  , bcSpikeConfig = defaultSpikeConfig
  }

data BatchResult = BatchResult
  { brPassed :: Int
  , brFailed :: Int
  , brErrors :: [(TestProgram, String)]  -- (program, error message)
  } deriving (Show)

-- Run a list of test programs through Spike, collecting pass/fail counts.
-- Phase 1: "pass" means Spike exits with ExitSuccess.
runBatch :: BatchConfig -> [TestProgram] -> IO BatchResult
runBatch cfg progs = foldl' combine (BatchResult 0 0 []) <$> mapM runOne progs
  where
    combine (BatchResult p f es) (BatchResult p' f' es') =
      BatchResult (p+p') (f+f') (es<>es')
    runOne prog =
      withSystemTempFile "riscv-rig-XXXXXX.elf" $ \path _ -> do
        let full = prog
              { tpStartup     = defaultStartup
              , tpTrapHandler = defaultTrapHandler
              , tpExit        = defaultExit
              }
        writeElf full path
        result <- runSpike (bcSpikeConfig cfg) path
        return $ case srExitCode result of
          ExitSuccess   -> BatchResult 1 0 []
          ExitFailure n ->
            BatchResult 0 1
              [(prog, "Spike exited with code " <> show n
                      <> "\nstderr: " <> take 500 (srStderr result))]
