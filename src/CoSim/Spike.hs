module CoSim.Spike
  ( SpikeConfig(..)
  , defaultSpikeConfig
  , runSpike
  , SpikeResult(..)
  , parseSpikeLog
  , parseSpikeLogLine
  ) where

import CoSim.Types
import Core.Decode       (decode)
import Data.Text         (Text)
import qualified Data.Text as T
import Data.Word         (Word32, Word64)
import Data.Char         (isHexDigit)
import System.Process    (readProcessWithExitCode)
import System.Exit       (ExitCode(..))
import Text.Megaparsec
import Text.Megaparsec.Char
import qualified Text.Megaparsec.Char.Lexer as L
import Data.Void         (Void)
import Numeric           (readHex)

type Parser = Parsec Void Text

data SpikeConfig = SpikeConfig
  { scSpikePath :: FilePath
  , scISA       :: String     -- e.g. "rv64im"
  , scLogLevel  :: Bool       -- whether to pass -l flag
  } deriving (Show)

defaultSpikeConfig :: SpikeConfig
defaultSpikeConfig = SpikeConfig
  { scSpikePath = "spike"
  , scISA       = "rv64im"
  , scLogLevel  = True
  }

data SpikeResult = SpikeResult
  { srExitCode :: ExitCode
  , srLog      :: [LogEntry]
  , srStdout   :: String
  , srStderr   :: String
  } deriving (Show)

runSpike :: SpikeConfig -> FilePath -> IO SpikeResult
runSpike cfg elfPath = do
  let args = [ "--isa=" <> scISA cfg ]
              <> [ "-l" | scLogLevel cfg ]
              <> [ elfPath ]
  (exitCode, stdout, stderr) <-
    readProcessWithExitCode (scSpikePath cfg) args ""
  let logEntries = case parseSpikeLog (T.pack stderr) of
                     Right es -> es
                     Left _   -> []
  return SpikeResult
    { srExitCode = exitCode
    , srLog      = logEntries
    , srStdout   = stdout
    , srStderr   = stderr
    }

-- ── Spike log parsing (Megaparsec) ────────────────────────────────────

-- Spike log line format:
-- "core   0: 0x0000000080000000 (0x00000093) addi zero, zero, 0"
parseSpikeLogLine :: Text -> Either String LogEntry
parseSpikeLogLine line =
  case runParser spikeLogLineP "<spike-log>" line of
    Left err -> Left (errorBundlePretty err)
    Right e  -> Right e

parseSpikeLog :: Text -> Either String [LogEntry]
parseSpikeLog logText =
  let ls = filter (T.isPrefixOf "core") (T.lines logText)
  in  sequence (map parseSpikeLogLine ls)

spikeLogLineP :: Parser LogEntry
spikeLogLineP = do
  _       <- string "core"
  space1
  hartID  <- L.decimal
  _       <- char ':'
  space1
  pc      <- hexWord64
  space1
  rawInstr <- between (char '(') (char ')') hexWord32
  _       <- takeRest  -- discard assembly text
  let instr = case decode rawInstr of
                Right i -> Right i
                Left e  -> Left (show e)
  return LogEntry
    { leHartID   = fromIntegral (hartID :: Integer)
    , lePC       = pc
    , leRawInstr = rawInstr
    , leInstr    = instr
    , leDelta    = emptyDelta
    }
  where
    emptyDelta = StateDelta [] [] [] Nothing

hexWord64 :: Parser Word64
hexWord64 = do
  _ <- string "0x"
  digits <- takeWhile1P (Just "hex digit") isHexDigit
  case readHex (T.unpack digits) of
    [(v, "")] -> return v
    _         -> fail "invalid hex word64"

hexWord32 :: Parser Word32
hexWord32 = do
  _ <- string "0x"
  digits <- takeWhile1P (Just "hex digit") isHexDigit
  case readHex (T.unpack digits) of
    [(v, "")] -> return v
    _         -> fail "invalid hex word32"
