module CoSim.Shrink
  ( shrinkSequence
  ) where

import Core.Instruction (Instruction)

-- | Shrink an instruction sequence to a minimal subset that still satisfies
-- the predicate. Uses delta-debugging: repeatedly tries to remove single
-- instructions, keeping the removal if the predicate still holds.
shrinkSequence
  :: ([Instruction] -> IO Bool)
  -> [Instruction]
  -> IO [Instruction]
shrinkSequence pred_ initial = do
  initialHolds <- pred_ initial
  if not initialHolds
    then return initial
    else go initial
  where
    go [] = return []
    go current = do
      maybeSmaller <- tryRemoveOne pred_ current
      case maybeSmaller of
        Nothing      -> return current
        Just smaller -> go smaller

tryRemoveOne
  :: ([Instruction] -> IO Bool)
  -> [Instruction]
  -> IO (Maybe [Instruction])
tryRemoveOne _     []  = return Nothing
tryRemoveOne pred_ xs  = go 0
  where
    n = length xs
    go i
      | i >= n    = return Nothing
      | otherwise = do
          let candidate = take i xs <> drop (i + 1) xs
          holds <- pred_ candidate
          if holds
            then return (Just candidate)
            else go (i + 1)
