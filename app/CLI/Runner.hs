module CLI.Runner (runCommand) where

import CLI.Options
import Core.Instruction          (Extension(..))
import Generator.Types           (defaultConfig, GeneratorConfig(..))
import Generator.Seed            (newRandomSeed, seedFromWord64)
import Generator.Random          (generateSequence)
import Coverage.Accumulator      (newAccumulator, recordCoverage, snapshotCoverage)
import Coverage.Classify         (classifySequence)
import Coverage.Analysis         (renderSummary)
import CoSim.Batch               (BatchConfig(..), defaultBatchConfig, runBatch, brPassed, brFailed)
import CoSim.Spike               (defaultSpikeConfig, SpikeConfig(..))
import CoSim.Oracle              (CoSimOracle(..))
import ELF.FlatBinary            (TestProgram(..), defaultStartup, defaultTrapHandler, defaultExit)
import Control.Concurrent.STM    (atomically)
import qualified Data.Set as Set
import System.Directory          (createDirectoryIfMissing)

runCommand :: Command -> IO ()
runCommand CmdVersion = putStrLn "riscv-rig 0.1.0"

runCommand (CmdGenerate opts) = do
  createDirectoryIfMissing True (goOutputDir opts)
  seed <- maybe newRandomSeed (return . seedFromWord64) (goSeed opts)
  let cfg = defaultConfig
        { gcExtensions = parseExtensions (goExtensions opts)
        , gcSeed       = seed
        }
  mapM_ (\i -> do
    seq_ <- generateSequence cfg
    let _prog = TestProgram
          { tpStartup     = defaultStartup
          , tpTrapHandler = defaultTrapHandler
          , tpTestBody    = seq_
          , tpExit        = defaultExit
          }
    putStrLn ("Generated sequence " <> show (i :: Int)
              <> " (" <> show (length seq_) <> " instructions)")
    ) [1..goCount opts]

runCommand (CmdServer opts) = runServer opts

runCommand (CmdRun opts) = do
  createDirectoryIfMissing True (roOutputDir opts)
  seed <- maybe newRandomSeed (return . seedFromWord64) (roSeed opts)
  let cfg = defaultConfig
        { gcExtensions = parseExtensions (roExtensions opts)
        , gcSeed       = seed
        , gcMinLength  = roMinLen opts
        , gcMaxLength  = roMaxLen opts
        }
      batchCfg = defaultBatchConfig
        { bcOracles     = [OracleSpike (roSpikePath opts)]
        , bcSpikeConfig = defaultSpikeConfig { scSpikePath = roSpikePath opts }
        }
  acc <- newAccumulator

  mapM_ (\roundN -> do
    putStrLn ("Round " <> show (roundN :: Int) <> "/" <> show (roRounds opts))
    seqs <- mapM (\_ -> generateSequence cfg) [1..10 :: Int]
    let progs = map (\s -> TestProgram
                      { tpStartup     = []
                      , tpTrapHandler = []
                      , tpTestBody    = s
                      , tpExit        = []
                      }) seqs
    result <- runBatch batchCfg progs
    let allBins = concatMap classifySequence seqs
    atomically $ recordCoverage acc allBins
    putStrLn ("  Passed: " <> show (brPassed result)
              <> "  Failed: " <> show (brFailed result))
    snap <- snapshotCoverage acc
    putStr (renderSummary snap)
    ) [1..roRounds opts]

parseExtensions :: [String] -> Set.Set Extension
parseExtensions exts =
  Set.fromList (RV64I : map parseExt exts)
  where
    parseExt "M" = RV64M
    parseExt "A" = RV64A
    parseExt "F" = RV64F
    parseExt "D" = RV64D
    parseExt "C" = RV64C
    parseExt "P" = RVPriv
    parseExt _   = RV64I

runServer :: ServerOptions -> IO ()
runServer opts =
  putStrLn ("riscv-rig server starting on port " <> show (soPort opts) <> " (not yet implemented)")
