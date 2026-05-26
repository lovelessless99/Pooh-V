module ELF.FlatBinary
  ( TestProgram(..)
  , generateElf
  , writeElf
  , defaultStartup
  , defaultTrapHandler
  , defaultExit
  , loadAddress
  , tohostAddress
  ) where

import Core.Types
import Core.Instruction
import Core.Encode      (encode)
import Data.Binary.Put
import Data.ByteString.Lazy (ByteString)
import qualified Data.ByteString.Lazy as BL
import Data.Word        (Word32, Word64)
import Data.Bits        ((.&.), complement)
import Control.Monad    (replicateM_)

loadAddress   :: Word64
loadAddress   = 0x80000000

tohostAddress :: Word64
tohostAddress = 0x80001000

data TestProgram = TestProgram
  { tpStartup     :: [Instruction]
  , tpTrapHandler :: [Instruction]
  , tpTestBody    :: [Instruction]
  , tpExit        :: [Instruction]
  } deriving (Show)

-- Assemble all instructions into a flat list of Word32
assembleProgram :: TestProgram -> [Word32]
assembleProgram prog = map encode $
  tpStartup prog <> tpTrapHandler prog <> tpTestBody prog <> tpExit prog

-- Write ELF to file
writeElf :: TestProgram -> FilePath -> IO ()
writeElf prog path = do
  bs <- generateElf prog path
  BL.writeFile path bs

-- Generate ELF bytes (also returns them for testing)
generateElf :: TestProgram -> FilePath -> IO ByteString
generateElf prog _ = do
  let instrs    = assembleProgram prog
      codeBytes = runPut (mapM_ putWord32le instrs)
      cs        = fromIntegral (BL.length codeBytes) :: Word64
  return (buildElf codeBytes cs)

buildElf :: ByteString -> Word64 -> ByteString
buildElf codeBytes cs = runPut $ do
  -- ── ELF Header (64 bytes) ─────────────────────────────────────────
  putWord8 0x7F; putWord8 0x45; putWord8 0x4C; putWord8 0x46  -- magic: \x7fELF
  putWord8 2          -- EI_CLASS: 64-bit
  putWord8 1          -- EI_DATA: little-endian
  putWord8 1          -- EI_VERSION
  putWord8 0          -- EI_OSABI: none
  replicateM_ 8 (putWord8 0)  -- padding
  putWord16le 2       -- e_type: ET_EXEC
  putWord16le 0xF3    -- e_machine: EM_RISCV
  putWord32le 1       -- e_version
  putWord64le loadAddress       -- e_entry
  putWord64le 64                -- e_phoff: program headers at byte 64
  putWord64le (align8 (176 + cs + 103))  -- e_shoff: section headers
  putWord32le 0       -- e_flags
  putWord16le 64      -- e_ehsize
  putWord16le 56      -- e_phentsize
  putWord16le 2       -- e_phnum
  putWord16le 64      -- e_shentsize
  putWord16le 6       -- e_shnum
  putWord16le 5       -- e_shstrndx

  -- ── Program Header 1: .text PT_LOAD RX (56 bytes) ─────────────────
  putWord32le 1       -- p_type: PT_LOAD
  putWord32le 5       -- p_flags: PF_R(4) | PF_X(1)
  putWord64le 176     -- p_offset
  putWord64le loadAddress
  putWord64le loadAddress
  putWord64le cs
  putWord64le cs
  putWord64le 0x1000  -- p_align: 4096

  -- ── Program Header 2: .data PT_LOAD RW (56 bytes) ─────────────────
  putWord32le 1       -- p_type: PT_LOAD
  putWord32le 6       -- p_flags: PF_R(4) | PF_W(2)
  putWord64le (176 + cs)
  putWord64le tohostAddress
  putWord64le tohostAddress
  putWord64le 8
  putWord64le 8
  putWord64le 0x1000

  -- ── .text ─────────────────────────────────────────────────────────
  putLazyByteString codeBytes

  -- ── .data: tohost (8 bytes, initially 0) ──────────────────────────
  putWord64le 0

  -- ── .symtab (2 × 24 = 48 bytes) ───────────────────────────────────
  -- Entry 0: NULL
  putWord32le 0; putWord8 0; putWord8 0; putWord16le 0
  putWord64le 0; putWord64le 0
  -- Entry 1: tohost
  putWord32le 1        -- st_name: "tohost" at strtab[1]
  putWord8 0x11        -- STB_GLOBAL(1<<4) | STT_OBJECT(1)
  putWord8 0
  putWord16le 2        -- st_shndx = .data section
  putWord64le tohostAddress
  putWord64le 8

  -- ── .strtab: "\x00tohost\x00" (8 bytes) ───────────────────────────
  putWord8 0
  mapM_ putWord8 [0x74,0x6F,0x68,0x6F,0x73,0x74]  -- "tohost"
  putWord8 0

  -- ── .shstrtab: "\x00.text\x00.data\x00.symtab\x00.strtab\x00.shstrtab\x00"
  -- Offsets: 0=null 1=.text 7=.data 13=.symtab 21=.strtab 29=.shstrtab  (39 bytes)
  putWord8 0
  mapM_ putWord8 (map (fromIntegral . fromEnum) ".text")    >> putWord8 0
  mapM_ putWord8 (map (fromIntegral . fromEnum) ".data")    >> putWord8 0
  mapM_ putWord8 (map (fromIntegral . fromEnum) ".symtab")  >> putWord8 0
  mapM_ putWord8 (map (fromIntegral . fromEnum) ".strtab")  >> putWord8 0
  mapM_ putWord8 (map (fromIntegral . fromEnum) ".shstrtab") >> putWord8 0

  -- ── Padding to 8-byte alignment ────────────────────────────────────
  let currentOffset = 176 + cs + 103
      padNeeded     = fromIntegral ((8 - currentOffset `mod` 8) `mod` 8) :: Int
  replicateM_ padNeeded (putWord8 0)

  -- ── Section Header Table (6 × 64 = 384 bytes) ──────────────────────
  let textOff  = 176
      dataOff  = 176 + cs
      symOff   = dataOff + 8
      strOff   = symOff  + 48
      shStrOff = strOff  + 8

  -- Section 0: NULL
  putWord32le 0
  replicateM_ 60 (putWord8 0)

  -- Section 1: .text  SHT_PROGBITS, SHF_ALLOC|SHF_EXECINSTR
  putWord32le 1;  putWord32le 1;  putWord64le 6
  putWord64le loadAddress; putWord64le textOff; putWord64le cs
  putWord32le 0;  putWord32le 0;  putWord64le 4;  putWord64le 0

  -- Section 2: .data  SHT_PROGBITS, SHF_ALLOC|SHF_WRITE
  putWord32le 7;  putWord32le 1;  putWord64le 3
  putWord64le tohostAddress; putWord64le dataOff; putWord64le 8
  putWord32le 0;  putWord32le 0;  putWord64le 8;  putWord64le 0

  -- Section 3: .symtab  SHT_SYMTAB
  putWord32le 13; putWord32le 2;  putWord64le 0
  putWord64le 0;  putWord64le symOff; putWord64le 48
  putWord32le 4;  putWord32le 1;  putWord64le 8;  putWord64le 24

  -- Section 4: .strtab  SHT_STRTAB
  putWord32le 21; putWord32le 3;  putWord64le 0
  putWord64le 0;  putWord64le strOff; putWord64le 8
  putWord32le 0;  putWord32le 0;  putWord64le 1;  putWord64le 0

  -- Section 5: .shstrtab  SHT_STRTAB
  putWord32le 29; putWord32le 3;  putWord64le 0
  putWord64le 0;  putWord64le shStrOff; putWord64le 39
  putWord32le 0;  putWord32le 0;  putWord64le 1;  putWord64le 0

-- ── Startup / Exit templates ──────────────────────────────────────────

-- Minimal startup: set up stack pointer (sp = 0x80010000)
defaultStartup :: [Instruction]
defaultStartup =
  [ LUI sp (Imm20 0x80010)   -- sp = 0x80010000
  , ADDI sp sp (Imm12 0)     -- no-op; explicit for clarity
  ]

-- Minimal trap handler: just return via MRET
defaultTrapHandler :: [Instruction]
defaultTrapHandler = [MRET]

-- HTIF exit: write 1 to tohost, then spin
defaultExit :: [Instruction]
defaultExit =
  [ LUI  t0 (Imm20 0x80001)    -- t0 = 0x80001000 (tohost)
  , ADDI t1 x0 (Imm12 1)       -- t1 = 1 (HTIF success)
  , SW   t1 t0 (Imm12 0)       -- mem[t0] = 1
  , JAL  x0 (Imm21 0)          -- infinite loop
  ]

-- ── Helpers ───────────────────────────────────────────────────────────

align8 :: Word64 -> Word64
align8 x = (x + 7) .&. complement 7
