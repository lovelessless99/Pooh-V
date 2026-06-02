module Main (main) where

import Test.Tasty
import qualified Test.Integration.Smoke as Smoke

main :: IO ()
main = defaultMain $ testGroup "pooh-v-integration" [Smoke.tests]
