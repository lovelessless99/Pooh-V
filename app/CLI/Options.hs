module CLI.Options
  ( Command(..)
  , RunOptions(..)
  , GenerateOptions(..)
  , ServerOptions(..)
  , parseOptions
  ) where

import Options.Applicative
import Data.Word (Word64)

data Command
  = CmdRun      RunOptions
  | CmdGenerate GenerateOptions
  | CmdServer   ServerOptions
  | CmdVersion
  deriving (Show)

data RunOptions = RunOptions
  { roExtensions :: [String]
  , roRounds     :: Int
  , roSeed       :: Maybe Word64
  , roMinLen     :: Int
  , roMaxLen     :: Int
  , roSpikePath  :: FilePath
  , roOutputDir  :: FilePath
  } deriving (Show)

data GenerateOptions = GenerateOptions
  { goExtensions :: [String]
  , goCount      :: Int
  , goSeed       :: Maybe Word64
  , goOutputDir  :: FilePath
  } deriving (Show)

data ServerOptions = ServerOptions
  { soPort :: Int
  } deriving (Show)

parseOptions :: IO Command
parseOptions = execParser opts
  where
    opts = info (commandP <**> helper)
      (fullDesc
       <> progDesc "RISC-V Random Instruction Generator"
       <> header   "pooh-v -- SMT-guided RISC-V test generator")

commandP :: Parser Command
commandP = subparser
  ( command "run"
      (info (CmdRun <$> runOptionsP)
            (progDesc "Generate and co-simulate with Spike"))
  <> command "generate"
      (info (CmdGenerate <$> generateOptionsP)
            (progDesc "Generate ELF files without running co-simulation"))
  <> command "server"
      (info (CmdServer <$> serverOptionsP)
            (progDesc "Start REST API server"))
  <> command "version"
      (info (pure CmdVersion) (progDesc "Print version"))
  )

runOptionsP :: Parser RunOptions
runOptionsP = RunOptions
  <$> many (strOption (long "ext" <> short 'e' <> metavar "EXT"
                       <> help "Enable extension (M, A, F, D, C)"))
  <*> option auto (long "rounds" <> short 'n' <> metavar "N"
                   <> value 10 <> showDefault
                   <> help "Number of rounds to run")
  <*> optional (option auto (long "seed" <> metavar "SEED"
                              <> help "Fixed seed for reproducibility"))
  <*> option auto (long "min-len" <> metavar "N" <> value 10 <> showDefault
                   <> help "Minimum sequence length")
  <*> option auto (long "max-len" <> metavar "N" <> value 50 <> showDefault
                   <> help "Maximum sequence length")
  <*> strOption (long "spike" <> metavar "PATH" <> value "spike" <> showDefault
                 <> help "Path to spike binary")
  <*> strOption (long "output" <> short 'o' <> metavar "DIR" <> value "output"
                 <> showDefault <> help "Output directory")

serverOptionsP :: Parser ServerOptions
serverOptionsP = ServerOptions
  <$> option auto (long "port" <> short 'p' <> metavar "PORT"
                   <> value 8080 <> showDefault <> help "Port to listen on")

generateOptionsP :: Parser GenerateOptions
generateOptionsP = GenerateOptions
  <$> many (strOption (long "ext" <> short 'e' <> metavar "EXT"
                       <> help "Enable extension"))
  <*> option auto (long "count" <> short 'n' <> metavar "N"
                   <> value 10 <> showDefault <> help "Number of ELFs to generate")
  <*> optional (option auto (long "seed" <> metavar "SEED"
                              <> help "Fixed seed"))
  <*> strOption (long "output" <> short 'o' <> metavar "DIR" <> value "output"
                 <> showDefault <> help "Output directory")
