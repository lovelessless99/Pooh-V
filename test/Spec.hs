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
import qualified Test.Coverage.Classify    as Classify
import qualified Test.ELF.FlatBinary    as ELFTest
import qualified Test.CoSim.Spike       as SpikeTest
import qualified Test.Core.ExtDeps      as ExtDeps
import qualified Test.Core.PMA          as PMA
import qualified Test.CoSim.Shrink      as Shrink
import qualified Test.Scenario.Registry as Registry
import qualified Test.Coverage.Bandit      as Bandit
import qualified Test.Generator.Guided     as Guided

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
  , Classify.tests
  , ELFTest.tests
  , SpikeTest.tests
  , ExtDeps.tests
  , PMA.tests
  , Shrink.tests
  , Registry.tests
  , Bandit.tests
  , Guided.tests
  ]
