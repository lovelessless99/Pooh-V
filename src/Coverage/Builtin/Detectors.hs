module Coverage.Builtin.Detectors
  ( detectLrscPair
  , detectLrscSuccess
  , detectLrscFail
  , detectLoadUse
  , detectBranchTaken
  , detectBranchNotTaken
  , detectBackwardBranch
  , detectForwardBranch
  , detectCallReturn
  , detectTailCall
  , detectFenceBeforeAtomic
  , detectExceptionReturn
  , detectWfi
  , detectFusion
  , detectCsrRmw
  ) where

import Core.Instruction (Instruction(..))
import Core.Types       (Register(..), Imm13(..), unReg)
import Data.List        (tails)

-- ── Helpers ────────────────────────────────────────────────────────────────

isLr :: Instruction -> Bool
isLr (LR_W {}) = True
isLr (LR_D {}) = True
isLr _         = False

isSc :: Instruction -> Bool
isSc (SC_W {}) = True
isSc (SC_D {}) = True
isSc _         = False

-- Extract the destination register of an SC, if it is one.
scRd :: Instruction -> Maybe Register
scRd (SC_W rd _ _ _) = Just rd
scRd (SC_D rd _ _ _) = Just rd
scRd _               = Nothing

isLoad :: Instruction -> Bool
isLoad i = case i of
  LB{}  -> True; LH{}  -> True; LW{}  -> True; LD{}  -> True
  LBU{} -> True; LHU{} -> True; LWU{} -> True
  _     -> False

-- Destination register of a load (first field for all loads).
loadRd :: Instruction -> Maybe Register
loadRd i = case i of
  LB  rd _ _ -> Just rd; LH  rd _ _ -> Just rd
  LW  rd _ _ -> Just rd; LD  rd _ _ -> Just rd
  LBU rd _ _ -> Just rd; LHU rd _ _ -> Just rd
  LWU rd _ _ -> Just rd
  _           -> Nothing

-- Source registers used by an instruction (for load-use check).
-- We only need to detect whether the load's destination appears as a source
-- in the immediately following instruction.
usesReg :: Register -> Instruction -> Bool
usesReg r i = case i of
  ADD  _ rs1 rs2   -> r == rs1 || r == rs2
  SUB  _ rs1 rs2   -> r == rs1 || r == rs2
  ADDI _ rs1 _     -> r == rs1
  ADDIW _ rs1 _    -> r == rs1
  ADDW _ rs1 rs2   -> r == rs1 || r == rs2
  SUBW _ rs1 rs2   -> r == rs1 || r == rs2
  AND  _ rs1 rs2   -> r == rs1 || r == rs2
  OR   _ rs1 rs2   -> r == rs1 || r == rs2
  XOR  _ rs1 rs2   -> r == rs1 || r == rs2
  ANDI _ rs1 _     -> r == rs1
  ORI  _ rs1 _     -> r == rs1
  XORI _ rs1 _     -> r == rs1
  SLL  _ rs1 rs2   -> r == rs1 || r == rs2
  SRL  _ rs1 rs2   -> r == rs1 || r == rs2
  SRA  _ rs1 rs2   -> r == rs1 || r == rs2
  SLLI _ rs1 _     -> r == rs1
  SRLI _ rs1 _     -> r == rs1
  SRAI _ rs1 _     -> r == rs1
  SLLIW _ rs1 _    -> r == rs1
  SRLIW _ rs1 _    -> r == rs1
  SRAIW _ rs1 _    -> r == rs1
  SLLW _ rs1 rs2   -> r == rs1 || r == rs2
  SRLW _ rs1 rs2   -> r == rs1 || r == rs2
  SRAW _ rs1 rs2   -> r == rs1 || r == rs2
  SLT  _ rs1 rs2   -> r == rs1 || r == rs2
  SLTU _ rs1 rs2   -> r == rs1 || r == rs2
  SLTI _ rs1 _     -> r == rs1
  SLTIU _ rs1 _    -> r == rs1
  LB   _ rs1 _     -> r == rs1
  LH   _ rs1 _     -> r == rs1
  LW   _ rs1 _     -> r == rs1
  LD   _ rs1 _     -> r == rs1
  LBU  _ rs1 _     -> r == rs1
  LHU  _ rs1 _     -> r == rs1
  LWU  _ rs1 _     -> r == rs1
  SB   rs2 rs1 _   -> r == rs1 || r == rs2
  SH   rs2 rs1 _   -> r == rs1 || r == rs2
  SW   rs2 rs1 _   -> r == rs1 || r == rs2
  SD   rs2 rs1 _   -> r == rs1 || r == rs2
  BEQ  rs1 rs2 _   -> r == rs1 || r == rs2
  BNE  rs1 rs2 _   -> r == rs1 || r == rs2
  BLT  rs1 rs2 _   -> r == rs1 || r == rs2
  BGE  rs1 rs2 _   -> r == rs1 || r == rs2
  BLTU rs1 rs2 _   -> r == rs1 || r == rs2
  BGEU rs1 rs2 _   -> r == rs1 || r == rs2
  JALR _ rs1 _     -> r == rs1
  MUL  _ rs1 rs2   -> r == rs1 || r == rs2
  MULH _ rs1 rs2   -> r == rs1 || r == rs2
  MULHSU _ rs1 rs2 -> r == rs1 || r == rs2
  MULHU _ rs1 rs2  -> r == rs1 || r == rs2
  DIV  _ rs1 rs2   -> r == rs1 || r == rs2
  DIVU _ rs1 rs2   -> r == rs1 || r == rs2
  REM  _ rs1 rs2   -> r == rs1 || r == rs2
  REMU _ rs1 rs2   -> r == rs1 || r == rs2
  MULW _ rs1 rs2   -> r == rs1 || r == rs2
  DIVW _ rs1 rs2   -> r == rs1 || r == rs2
  DIVUW _ rs1 rs2  -> r == rs1 || r == rs2
  REMW _ rs1 rs2   -> r == rs1 || r == rs2
  REMUW _ rs1 rs2  -> r == rs1 || r == rs2
  LR_W _ rs1 _     -> r == rs1
  LR_D _ rs1 _     -> r == rs1
  SC_W _ rs1 rs2 _ -> r == rs1 || r == rs2
  SC_D _ rs1 rs2 _ -> r == rs1 || r == rs2
  CSRRW _ _ rs1    -> r == rs1
  CSRRS _ _ rs1    -> r == rs1
  CSRRC _ _ rs1    -> r == rs1
  SFENCE_VMA rs1 rs2 -> r == rs1 || r == rs2
  _                -> False

isBranch :: Instruction -> Bool
isBranch i = case i of
  BEQ{}  -> True; BNE{}  -> True; BLT{}  -> True
  BGE{}  -> True; BLTU{} -> True; BGEU{} -> True
  _      -> False

branchOffset :: Instruction -> Maybe Int
branchOffset i = case i of
  BEQ  _ _ (Imm13 off) -> Just (fromIntegral off)
  BNE  _ _ (Imm13 off) -> Just (fromIntegral off)
  BLT  _ _ (Imm13 off) -> Just (fromIntegral off)
  BGE  _ _ (Imm13 off) -> Just (fromIntegral off)
  BLTU _ _ (Imm13 off) -> Just (fromIntegral off)
  BGEU _ _ (Imm13 off) -> Just (fromIntegral off)
  _                    -> Nothing

isAtomic :: Instruction -> Bool
isAtomic i = case i of
  LR_W{}      -> True; LR_D{}      -> True
  SC_W{}      -> True; SC_D{}      -> True
  AMOSWAP_W{} -> True; AMOADD_W{}  -> True; AMOXOR_W{}  -> True
  AMOAND_W{}  -> True; AMOOR_W{}   -> True; AMOMIN_W{}  -> True
  AMOMAX_W{}  -> True; AMOMINU_W{} -> True; AMOMAXU_W{} -> True
  AMOSWAP_D{} -> True; AMOADD_D{}  -> True; AMOXOR_D{}  -> True
  AMOAND_D{}  -> True; AMOOR_D{}   -> True; AMOMIN_D{}  -> True
  AMOMAX_D{}  -> True; AMOMINU_D{} -> True; AMOMAXU_D{} -> True
  _           -> False

isFence :: Instruction -> Bool
isFence (FENCE _ _) = True
isFence FENCE_I     = True
isFence _           = False

-- Extract destination register of LUI/AUIPC.
upperImmRd :: Instruction -> Maybe Register
upperImmRd (LUI   rd _) = Just rd
upperImmRd (AUIPC rd _) = Just rd
upperImmRd _            = Nothing

-- Check whether an ADDI targets the given destination register.
addiRd :: Instruction -> Maybe Register
addiRd (ADDI rd _ _) = Just rd
addiRd _             = Nothing

-- ── Detectors ──────────────────────────────────────────────────────────────

-- | Any LR followed (anywhere) by any SC in the sequence.
detectLrscPair :: [Instruction] -> Bool
detectLrscPair instrs = any isLr instrs && any isSc instrs

-- | LR/SC pair where at least one SC has rd /= x0 (result checked).
detectLrscSuccess :: [Instruction] -> Bool
detectLrscSuccess instrs =
  detectLrscPair instrs &&
  any (\i -> case scRd i of
               Just rd -> unReg rd /= 0
               Nothing -> False) instrs

-- | LR/SC pair where at least one SC has rd == x0 (result discarded).
detectLrscFail :: [Instruction] -> Bool
detectLrscFail instrs =
  detectLrscPair instrs &&
  any (\i -> case scRd i of
               Just rd -> unReg rd == 0
               Nothing -> False) instrs

-- | A load immediately followed by an instruction that reads the load's rd.
detectLoadUse :: [Instruction] -> Bool
detectLoadUse instrs =
  any checkPair (zip instrs (drop 1 instrs))
  where
    checkPair (a, b) = case loadRd a of
      Just rd -> usesReg rd b
      Nothing -> False

-- | Backward branch (negative offset) — heuristically "taken" in loop bodies.
detectBackwardBranch :: [Instruction] -> Bool
detectBackwardBranch instrs =
  any (\i -> case branchOffset i of
               Just off -> off < 0
               Nothing  -> False) instrs

-- | Forward branch (positive offset).
detectForwardBranch :: [Instruction] -> Bool
detectForwardBranch instrs =
  any (\i -> case branchOffset i of
               Just off -> off > 0
               Nothing  -> False) instrs

-- | Alias: backward branches are typically taken in loops.
detectBranchTaken :: [Instruction] -> Bool
detectBranchTaken = detectBackwardBranch

-- | Alias: forward branches are typically not-taken (fall-through).
detectBranchNotTaken :: [Instruction] -> Bool
detectBranchNotTaken = detectForwardBranch

-- | Any JAL or JALR instruction present.
detectCallReturn :: [Instruction] -> Bool
detectCallReturn instrs = any isJump instrs
  where
    isJump (JAL  _ _)   = True
    isJump (JALR _ _ _) = True
    isJump _            = False

-- | JALR with rd = x0 (tail call / indirect jump, result discarded).
detectTailCall :: [Instruction] -> Bool
detectTailCall instrs =
  any (\i -> case i of
               JALR rd _ _ -> unReg rd == 0
               _           -> False) instrs

-- | FENCE immediately followed by an atomic instruction.
detectFenceBeforeAtomic :: [Instruction] -> Bool
detectFenceBeforeAtomic instrs =
  any (\(a, b) -> isFence a && isAtomic b) (zip instrs (drop 1 instrs))

-- | Any MRET or SRET instruction.
detectExceptionReturn :: [Instruction] -> Bool
detectExceptionReturn instrs = any isXret instrs
  where
    isXret MRET = True
    isXret SRET = True
    isXret _    = False

-- | Any WFI instruction.
detectWfi :: [Instruction] -> Bool
detectWfi = any (== WFI)

-- | LUI or AUIPC immediately followed by ADDI to the same destination register.
detectFusion :: [Instruction] -> Bool
detectFusion instrs =
  any checkPair (zip instrs (drop 1 instrs))
  where
    checkPair (a, b) = case (upperImmRd a, addiRd b) of
      (Just rdA, Just rdB) -> rdA == rdB
      _                    -> False

-- | Any CSRRS or CSRRC instruction (read-modify-write semantics).
detectCsrRmw :: [Instruction] -> Bool
detectCsrRmw instrs = any isCsrRmw instrs
  where
    isCsrRmw (CSRRS _ _ _) = True
    isCsrRmw (CSRRC _ _ _) = True
    isCsrRmw _             = False
