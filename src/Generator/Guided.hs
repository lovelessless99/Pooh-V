module Generator.Guided
  ( guidedInstruction
  , guidedSequence
  , binToConstraints
  ) where

import Coverage.Types       (CoverageBin(..), ValueCategory(..), SequencePattern(..))
import Coverage.Bandit      (BanditState, sampleTarget)
import Coverage.Classify    (classifySequence)
import Core.Instruction     (Instruction(..))
import Core.Types           (Register(..), Imm12(..), x0, x1, x2, AqRl(..))
import Constraint.Types     (ConstraintDef(..), ConstraintSet, SymInstrParams(..),
                              InstrParams(..), addConstraint, emptyConstraintSet)
import Constraint.Solver    (solve)
import Generator.Types      (GeneratorConfig(..), InstrSequence)
import Generator.Random     (generateSequence)
import Generator.Seed       (deriveSeed)
import Data.SBV             ((.==), (.>), (.<), (.&&), (./=), literal, sRem)
import Data.Text            (Text)
import qualified Data.Set as Set

-- | Translate a ValueBin target into a ConstraintSet.
-- Returns Nothing if this bin type cannot be expressed as Z3 constraints.
binToConstraints :: CoverageBin -> Maybe ConstraintSet
binToConstraints bin = case bin of
  ValueBin Zero          -> Just $ imm (\s -> symImm s .== 0)                          "imm-zero"
  ValueBin One           -> Just $ imm (\s -> symImm s .== 1)                          "imm-one"
  ValueBin AllOnes       -> Just $ imm (\s -> symImm s .== literal (-1))               "imm-allones"
  ValueBin MaxPositive   -> Just $ imm (\s -> symImm s .== 2047)                       "imm-maxpos"
  ValueBin MinNegative   -> Just $ imm (\s -> symImm s .== literal (-2048))            "imm-minneg"
  ValueBin SmallPositive -> Just $ imm (\s -> symImm s .> 0 .&& symImm s .< 16)       "imm-small"
  ValueBin AlignedAddr   -> Just $ imm (\s -> symImm s .> 0 .&& symImm s `sRem` 4 .== 0) "imm-align"
  ValueBin UnalignedAddr -> Just $ imm (\s -> symImm s .> 0 .&& symImm s `sRem` 4 ./= 0) "imm-unalign"
  _                      -> Nothing
  where
    imm pred_ name =
      addConstraint (ConstraintDef name [] "" [] pred_) emptyConstraintSet

-- | Generate one instruction targeting a specific bin.
-- Returns Nothing when the bin is infeasible under the current config.
guidedInstruction :: CoverageBin -> GeneratorConfig -> IO (Maybe Instruction)
guidedInstruction bin cfg = case bin of
  OpcodeBin name       -> findOpcode name cfg
  ValueBin _           -> case binToConstraints bin of
    Nothing -> return Nothing
    Just cs -> do
      mParams <- solve cs
      return $ fmap toAddi mParams
  PatternBin _         -> return Nothing
  OpcodeModeBin name _ -> findOpcode name cfg

-- | Generate a sequence, letting the bandit pick the target bin.
guidedSequence
  :: BanditState
  -> GeneratorConfig
  -> Int
  -> IO (InstrSequence, [CoverageBin])
guidedSequence bs cfg len = do
  target  <- sampleTarget bs
  instrs  <- buildSeq target cfg len
  let bins = classifySequence instrs
  return (instrs, bins)

-- ── Helpers ───────────────────────────────────────────────────────────────

-- Find first instruction in a big random sequence whose opcode matches.
-- Tries up to 20 seeds to improve the chance of finding the target opcode.
findOpcode :: Text -> GeneratorConfig -> IO (Maybe Instruction)
findOpcode name cfg = go (20 :: Int) cfg
  where
    go 0 _    = return Nothing
    go n cur  = do
      let bigCfg = cur { gcMinLength = 50, gcMaxLength = 50 }
      seq_   <- generateSequence bigCfg
      let matches = filter (\i -> instrOpcodeName i == name) seq_
      case matches of
        (x:_) -> return (Just x)
        []    -> go (n - 1) (cur { gcSeed = deriveSeed (gcSeed cur) "findOpcode" })
    instrOpcodeName i = case classifySequence [i] of
      (OpcodeBin n : _) -> n
      _                 -> ""

-- Convert Z3 InstrParams to a concrete ADDI instruction
toAddi :: InstrParams -> Instruction
toAddi p =
  ADDI (Register (ipRd  p `mod` 32))
       (Register (ipRs1 p `mod` 32))
       (Imm12 (fromIntegral (ipImm p)))

-- Build a sequence targeting a specific bin type
buildSeq :: CoverageBin -> GeneratorConfig -> Int -> IO InstrSequence
buildSeq (PatternBin pat) cfg len = case pat of
  LrscPair -> do
    let lr  = LR_D x1 x2 AqRlAcquire
        sc  = SC_D x1 x2 x1 AqRlRelease
    mid <- take (max 0 (len - 2)) <$> generateSequence cfg
    return (lr : mid <> [sc])
  LoadUseDependency -> do
    let ld   = LD x1 x2 (Imm12 0)
        use_ = ADD x0 x1 x2
    rest <- take (max 0 (len - 2)) <$> generateSequence cfg
    return (ld : use_ : rest)
  _ -> generateSequence cfg
buildSeq _ cfg _ = generateSequence cfg
