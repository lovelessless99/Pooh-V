module Main (main) where

import Test.Tasty
import qualified Test.Core.Encode       as CoreEncode
import qualified Test.Core.Decode       as CoreDecode
import qualified Test.Core.Atomic       as Atomic
import qualified Test.Core.FloatInstr   as FloatInstr
import qualified Test.Core.Compressed   as Compressed
import qualified Test.Constraint.Solver as CSolver
import qualified Test.Generator.Random  as GenRandom
import qualified Test.Coverage.Accumulator as CovAccum
import qualified Test.Coverage.Bins        as CovBins
import qualified Test.ELF.FlatBinary    as ELFTest
import qualified Test.CoSim.Spike       as SpikeTest

main :: IO ()
main = defaultMain $ testGroup "riscv-rig"
  [ CoreEncode.tests
  , CoreDecode.tests
  , Atomic.tests
  , FloatInstr.tests
  , Compressed.tests
  , CSolver.tests
  , GenRandom.tests
  , CovAccum.tests
  , CovBins.tests
  , ELFTest.tests
  , SpikeTest.tests
  ]
