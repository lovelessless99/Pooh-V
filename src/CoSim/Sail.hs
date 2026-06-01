module CoSim.Sail
  ( SailConfig(..)
  , SailISA(..)
  , defaultSailConfig
  , checkSailExists
  , runSail
  ) where

import CoSim.Spike      (SpikeResult(..))
import System.Exit      (ExitCode(..))
import System.Process   (readProcessWithExitCode)
import System.IO.Error  (tryIOError)
import Data.Time.Clock  (NominalDiffTime)

data SailISA = SailRV64GC | SailRV32GC
  deriving (Show, Eq)

data SailConfig = SailConfig
  { scSailPath :: FilePath
  , scSailISA  :: SailISA
  , scTimeout  :: NominalDiffTime
  }

defaultSailConfig :: SailConfig
defaultSailConfig = SailConfig
  { scSailPath = "sail-riscv"
  , scSailISA  = SailRV64GC
  , scTimeout  = 30
  }

checkSailExists :: IO Bool
checkSailExists = do
  result <- tryIOError (readProcessWithExitCode "sail-riscv" ["--help"] "")
  return $ case result of
    Left  _                      -> False
    Right (ExitSuccess,    _, _) -> True
    Right (ExitFailure _, _, _)  -> True

runSail :: SailConfig -> FilePath -> IO SpikeResult
runSail cfg elfPath = do
  let args = [ "--no-trace"
             , if scSailISA cfg == SailRV64GC then "rv64" else "rv32"
             , elfPath
             ]
  (exitCode, stdout, stderr) <- readProcessWithExitCode (scSailPath cfg) args ""
  return SpikeResult
    { srExitCode = exitCode
    , srStdout   = stdout
    , srStderr   = stderr
    , srLog      = []
    }
