module Main (main) where

import CLI.Options (parseOptions)
import CLI.Runner  (runCommand)

main :: IO ()
main = parseOptions >>= runCommand
