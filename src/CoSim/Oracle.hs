module CoSim.Oracle
  ( CoSimOracle(..)
  , OracleCapabilities(..)
  , oracleCapabilities
  , selectOracles
  ) where

import Core.Instruction (Instruction(..))

data CoSimOracle
  = OracleSpike     FilePath  -- path to spike binary
  | OracleSail      FilePath  -- path to sail-riscv binary
  | OracleQEMU      FilePath  -- path to qemu-system-riscv64 (limited)
  | OracleSoftFloat            -- pure Haskell IEEE 754 reference (Phase 2+)
  deriving (Show, Eq)

data OracleCapabilities = OracleCapabilities
  { supportsInterruptTiming  :: Bool
  , supportsFPExactSemantics :: Bool
  , supportsRVWMO            :: Bool
  , supportsPMAAttributes    :: Bool
  , supportsVectorExt        :: Bool
  } deriving (Show, Eq)

oracleCapabilities :: CoSimOracle -> OracleCapabilities
oracleCapabilities = \case
  OracleSpike     _ -> OracleCapabilities True  True  False True  False
  OracleSail      _ -> OracleCapabilities True  True  True  True  False
  OracleQEMU      _ -> OracleCapabilities False False False False False
  OracleSoftFloat   -> OracleCapabilities False True  False False False

-- Select oracles appropriate for the given instruction sequence.
-- Oracles that can't handle the sequence's characteristics are filtered out.
selectOracles :: [Instruction] -> [CoSimOracle] -> [CoSimOracle]
selectOracles instrs oracles =
  filter (\o -> canHandle (oracleCapabilities o)) oracles
  where
    hasFP  = any isFPInstr instrs
    hasInt = any isInterruptRelated instrs

    canHandle caps =
      (not hasFP  || supportsFPExactSemantics caps)
      && (not hasInt || supportsInterruptTiming  caps)

    isFPInstr :: Instruction -> Bool
    isFPInstr _ = False  -- Phase 1: no FP instructions

    isInterruptRelated :: Instruction -> Bool
    isInterruptRelated MRET = True
    isInterruptRelated WFI  = True
    isInterruptRelated _    = False
