module Generator.Seed
  ( Seed(..)
  , newRandomSeed
  , seedFromWord64
  , deriveSeed
  ) where

import Data.Bits   (xor)
import Data.Word   (Word64)
import System.Random (randomIO)

newtype Seed = Seed { unSeed :: Word64 }
  deriving (Show, Eq, Ord)

newRandomSeed :: IO Seed
newRandomSeed = Seed <$> randomIO

seedFromWord64 :: Word64 -> Seed
seedFromWord64 = Seed

-- Derive a child seed from a parent seed + label using FNV-1a hash.
-- Different labels from the same root give independent seeds.
deriveSeed :: Seed -> String -> Seed
deriveSeed (Seed root) label =
  Seed (foldl fnv1aStep root (map (fromIntegral . fromEnum) label))
  where
    fnv1aStep :: Word64 -> Word64 -> Word64
    fnv1aStep acc byte = (acc `xor` byte) * 0x00000100000001B3
