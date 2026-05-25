module Constraint.Solver
  ( solve
  , checkFeasibility
  , estimateDensity
  ) where

import Constraint.Types
import Data.SBV hiding (ConstraintSet, solve)
import Data.Maybe  (fromMaybe)

solve :: ConstraintSet -> IO (Maybe InstrParams)
solve cs = do
  result <- sat (buildQuery cs)
  return $ extractParams result

buildQuery :: ConstraintSet -> Symbolic ()
buildQuery cs = do
  params <- mkSymParams
  constrain $ symOpcode params .< 128
  constrain $ symRd     params .< 32
  constrain $ symRs1    params .< 32
  constrain $ symRs2    params .< 32
  constrain $ symFunct3 params .< 8
  constrain $ symFunct7 params .< 128
  mapM_ (\c -> constrain (cpredicate c params)) (constraints cs)

mkSymParams :: Symbolic SymInstrParams
mkSymParams = SymInstrParams
  <$> sWord8 "opcode"
  <*> sWord8 "rd"
  <*> sWord8 "rs1"
  <*> sWord8 "rs2"
  <*> sWord8 "funct3"
  <*> sWord8 "funct7"
  <*> sInt32 "imm"

extractParams :: SatResult -> Maybe InstrParams
extractParams result
  | modelExists result = Just InstrParams
      { ipOpcode = fromMaybe 0 (getModelValue "opcode" result)
      , ipRd     = fromMaybe 0 (getModelValue "rd"     result)
      , ipRs1    = fromMaybe 0 (getModelValue "rs1"    result)
      , ipRs2    = fromMaybe 0 (getModelValue "rs2"    result)
      , ipFunct3 = fromMaybe 0 (getModelValue "funct3" result)
      , ipFunct7 = fromMaybe 0 (getModelValue "funct7" result)
      , ipImm    = fromMaybe 0 (getModelValue "imm"    result)
      }
  | otherwise = Nothing

checkFeasibility :: ConstraintSet -> IO FeasibilityResult
checkFeasibility cs = do
  result <- sat (buildQuery cs)
  return $ if modelExists result
    then Feasible
    else Infeasible (map cname (constraints cs))

estimateDensity :: ConstraintSet -> Int -> IO Density
estimateDensity cs n = do
  solutions <- collectN cs n []
  let unique = length solutions
      r      = if n == 0 then 0.0 else fromIntegral unique / fromIntegral n
  return Density
    { sampleSize  = n
    , uniqueCount = unique
    , ratio       = r
    , assessment  = assess r
    }

collectN :: ConstraintSet -> Int -> [InstrParams] -> IO [InstrParams]
collectN _ 0 acc = return acc
collectN cs remaining acc = do
  result <- solve cs
  case result of
    Nothing -> return acc
    Just p  ->
      let blockClause prms =
            sNot $ symRd prms .== literal (ipRd p)
              .&& symRs1 prms .== literal (ipRs1 p)
              .&& symImm prms .== literal (ipImm p)
          blocked = ConstraintSet
            (ConstraintDef "block" [] "" [] blockClause : constraints cs)
      in  collectN blocked (remaining - 1) (p : acc)

assess :: Double -> DensityAssessment
assess r
  | r > 0.5   = HealthyDensity
  | r > 0.1   = TightConstraints
  | r > 0.0   = OverConstrained
  | otherwise = PossiblyExhausted
