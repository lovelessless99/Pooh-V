module Core.PMA
  ( MemoryType(..)
  , CacheabilityHint(..)
  , PMAEntry(..)
  , MemoryLayout(..)
  , defaultMemoryLayout
  , lookupPMA
  ) where

import Data.Word    (Word64)
import GHC.Generics (Generic)

data MemoryType
  = MainMemory   -- cacheable, coherent, idempotent
  | IOMemory     -- uncacheable, non-idempotent (read has side effects)
  | VacantMemory -- access raises access fault
  deriving (Show, Eq, Ord, Generic)

data CacheabilityHint
  = Cacheable
  | Uncacheable
  | WriteThrough
  deriving (Show, Eq, Ord, Generic)

data PMAEntry = PMAEntry
  { pmaBase       :: Word64
  , pmaSize       :: Word64
  , pmaType       :: MemoryType
  , pmaCacheable  :: CacheabilityHint
  , pmaExecutable :: Bool
  , pmaReadable   :: Bool
  , pmaWritable   :: Bool
  , pmaAtomic     :: Bool  -- supports LR/SC and AMO
  } deriving (Show, Eq, Generic)

data MemoryLayout = MemoryLayout
  { regions    :: [PMAEntry]
  , codeBase   :: Word64
  , dataBase   :: Word64
  , stackTop   :: Word64
  } deriving (Show, Eq, Generic)

-- Standard layout used by riscv-rig test programs
defaultMemoryLayout :: MemoryLayout
defaultMemoryLayout = MemoryLayout
  { regions =
      [ PMAEntry
          { pmaBase = 0x80000000, pmaSize = 0x10000000
          , pmaType = MainMemory, pmaCacheable = Cacheable
          , pmaExecutable = True, pmaReadable = True, pmaWritable = True, pmaAtomic = True
          }
      , PMAEntry
          { pmaBase = 0x10000000, pmaSize = 0x00001000
          , pmaType = IOMemory, pmaCacheable = Uncacheable
          , pmaExecutable = False, pmaReadable = True, pmaWritable = True, pmaAtomic = False
          }
      , PMAEntry
          { pmaBase = 0x02000000, pmaSize = 0x00010000
          , pmaType = IOMemory, pmaCacheable = Uncacheable
          , pmaExecutable = False, pmaReadable = True, pmaWritable = True, pmaAtomic = False
          }
      ]
  , codeBase = 0x80000000
  , dataBase = 0x80008000
  , stackTop = 0x80010000
  }

-- Find the PMA entry for a given physical address.
-- Returns Nothing if no region covers the address (implicitly VacantMemory).
lookupPMA :: Word64 -> MemoryLayout -> Maybe PMAEntry
lookupPMA addr layout =
  let matches e = addr >= pmaBase e && addr < pmaBase e + pmaSize e
  in case filter matches (regions layout) of
    []    -> Nothing
    (e:_) -> Just e
