module Main (main) where

import CLI.Options (parseOptions)
import CLI.Runner  (runCommand)
import System.IO   (hSetBuffering, stdout, stderr, BufferMode(..))

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  hSetBuffering stderr LineBuffering
  parseOptions >>= runCommand
