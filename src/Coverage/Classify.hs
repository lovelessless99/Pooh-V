module Coverage.Classify
  ( classifySequence
  ) where

import Coverage.Types    (CoverageBin(..), ValueCategory(..))
import Coverage.Detector (allDetectors, pdPattern, pdDetect)
import Core.Instruction  (Instruction(..))
import Core.Types        (Imm12(..))
import Data.List         (nub)
import Data.Text         (pack)
import GHC.Generics

-- | Classify a sequence into all coverage bins it hits.
-- Returns deduplicated list.
classifySequence :: [Instruction] -> [CoverageBin]
classifySequence []     = []
classifySequence instrs = nub $
  map instrOpcodeBin instrs
  <> patternBins instrs
  <> concatMap instrValueBins instrs

-- ── Opcode bin per instruction ────────────────────────────────────────────
-- Walk the Generic Rep of the instruction value to get the constructor name.

class GConName (f :: * -> *) where
  gConName :: f x -> String

instance Constructor c => GConName (C1 c f) where
  gConName m = conName m

instance GConName f => GConName (D1 c f) where
  gConName (M1 x) = gConName x

instance (GConName f, GConName g) => GConName (f :+: g) where
  gConName (L1 x) = gConName x
  gConName (R1 x) = gConName x

instrOpcodeBin :: Instruction -> CoverageBin
instrOpcodeBin i = OpcodeBin (pack (gConName (from i)))

-- ── Pattern bins ─────────────────────────────────────────────────────────

patternBins :: [Instruction] -> [CoverageBin]
patternBins instrs =
  [ PatternBin (pdPattern d)
  | d <- allDetectors
  , pdDetect d instrs
  ]

-- ── Value bins ────────────────────────────────────────────────────────────

instrValueBins :: Instruction -> [CoverageBin]
instrValueBins instr = case extractImm instr of
  Nothing  -> []
  Just imm -> map ValueBin (classifyImm imm)

extractImm :: Instruction -> Maybe Int
extractImm instr = case instr of
  ADDI  _ _ (Imm12 v) -> Just (fromIntegral v)
  ANDI  _ _ (Imm12 v) -> Just (fromIntegral v)
  ORI   _ _ (Imm12 v) -> Just (fromIntegral v)
  XORI  _ _ (Imm12 v) -> Just (fromIntegral v)
  SLTI  _ _ (Imm12 v) -> Just (fromIntegral v)
  SLTIU _ _ (Imm12 v) -> Just (fromIntegral v)
  LB    _ _ (Imm12 v) -> Just (fromIntegral v)
  LH    _ _ (Imm12 v) -> Just (fromIntegral v)
  LW    _ _ (Imm12 v) -> Just (fromIntegral v)
  LD    _ _ (Imm12 v) -> Just (fromIntegral v)
  LBU   _ _ (Imm12 v) -> Just (fromIntegral v)
  LHU   _ _ (Imm12 v) -> Just (fromIntegral v)
  LWU   _ _ (Imm12 v) -> Just (fromIntegral v)
  JALR  _ _ (Imm12 v) -> Just (fromIntegral v)
  SB    _ _ (Imm12 v) -> Just (fromIntegral v)
  SH    _ _ (Imm12 v) -> Just (fromIntegral v)
  SW    _ _ (Imm12 v) -> Just (fromIntegral v)
  SD    _ _ (Imm12 v) -> Just (fromIntegral v)
  FSW   _ _ (Imm12 v) -> Just (fromIntegral v)
  FSD   _ _ (Imm12 v) -> Just (fromIntegral v)
  _                   -> Nothing

classifyImm :: Int -> [ValueCategory]
classifyImm v = concatMap (\(cond, cat) -> if cond then [cat] else []) $
  [ (v == 0,                   Zero)
  , (v == 1,                   One)
  , (v == -1,                  AllOnes)
  , (v == 2047,                MaxPositive)
  , (v == -2048,               MinNegative)
  , (v > 0 && v < 16,          SmallPositive)
  , (v > 0 && v `mod` 4 == 0,  AlignedAddr)
  , (v > 0 && v `mod` 4 /= 0,  UnalignedAddr)
  ]
