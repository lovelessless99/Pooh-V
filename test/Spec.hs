module Main (main) where

import Test.Tasty
import qualified Test.Core.Encode       as CoreEncode
import qualified Test.Core.Decode       as CoreDecode
import qualified Test.Constraint.Solver as CSolver
import qualified Test.Generator.Random  as GenRandom
import qualified Test.Coverage.Accumulator as CovAccum
import qualified Test.ELF.FlatBinary    as ELFTest
import qualified Test.CoSim.Spike       as SpikeTest

main :: IO ()
main = defaultMain $ testGroup "riscv-rig"
  [ CoreEncode.tests
  , CoreDecode.tests
  , CSolver.tests
  , GenRandom.tests
  , CovAccum.tests
  , ELFTest.tests
  , SpikeTest.tests
  ]
