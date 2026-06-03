# RISC-V Random Instruction Generator (riscv-rig) — Complete Design Specification

**Date:** 2026-05-21  
**Status:** Draft  
**Target ISA:** RV64GC (I+M+A+F+D+C)，分階段擴充至全 RV64GCB + multi-core；RVV（Vector）列為 Phase 6 獨立子專案  

---

## 目錄

1. [動機與目標](#1-動機與目標)
2. [系統架構總覽](#2-系統架構總覽)
3. [核心 ISA 模型](#3-核心-isa-模型)
4. [記憶體模型](#4-記憶體模型)
5. [Constraint 系統](#5-constraint-系統)
6. [Scenario 系統](#6-scenario-系統)
7. [Generator](#7-generator)
8. [Coverage 模型](#8-coverage-模型)
9. [CoSim 引擎](#9-cosim-引擎)
10. [Coverage Optimizer](#10-coverage-optimizer)
11. [Multi-core 支援](#11-multi-core-支援)
12. [Privilege Level & Trap 處理](#12-privilege-level--trap-處理)
13. [特殊 Coverage 領域](#13-特殊-coverage-領域)
14. [Regression 管理](#14-regression-管理)
15. [輸出格式](#15-輸出格式)
16. [Extension 相依性系統](#16-extension-相依性系統)
17. [CLI 設計](#17-cli-設計)
18. [Web App 設計](#18-web-app-設計)
19. [專案結構與建構系統](#19-專案結構與建構系統)
20. [開發階段規劃](#20-開發階段規劃)

---

## 1. 動機與目標

### 1.1 為什麼需要這個工具

RISC-V 的開放性讓各種不同的實作百花齊放，但也帶來驗證的挑戰：每個實作都需要對抗相同的 corner case 空間，卻缺乏一個系統性的方法來探索這個空間。現有的方法有幾個問題：

- **手寫測試**：覆蓋率低，只測得到開發者想到的 case。
- **純 random**：能廣度覆蓋，但找不到深層的 corner case，無法保證測到 LR/SC + interrupt 這類複合場景。
- **Formal verification**：能證明正確性，但 state space 爆炸，難以應付複雜的 scenario。

本工具的核心思想是結合三種方法的優點：

```
Random generation  → 廣度、效率
Constraint solving → 深度、corner case 定向挖掘
Coverage guidance  → 確保沒有死角、可量化的完整性
```

### 1.2 設計哲學

**可解釋性優先**：每一個生成的測試序列，都能說明它為什麼被生成、它測試了什麼、它的 coverage 貢獻是什麼。不依賴黑盒的 AI 模型。

**ADT 是最好的文件**：RISC-V 指令集是一個 sum type，用 Haskell ADT 直接表達，讓 type system 成為 ISA spec 的一部分。GHC 的 exhaustive pattern match 警告在 compile time 告訴你是否漏掉了某個指令。

**Constraint 是一等公民**：constraint 可以組合、命名、版本控制、分類、獨立測試。加入新的 constraint 不需要改動任何現有程式碼。

**測試空間可視化**：coverage 不是一個數字，是一張地圖。要能看到哪裡已經探索過、哪裡還是空白、哪裡被 constraint 封住了。

### 1.3 目標功能列表

| 功能 | 說明 |
|---|---|
| RV64GC 完整指令 ADT | 型別安全的指令表示，encode/decode 雙向 |
| SMT-based constraint 系統 | Z3 求解，可組合的 eDSL |
| Scenario 系統 | 描述複雜測試意圖，可擴充至 1000+ scenarios |
| Extension 相依性解析 | 自動補齊依賴，交叉解空間探索 |
| Coverage 多維模型 | Opcode × Value × Sequence × Extension × Privilege × Memory type |
| Coverage Optimizer | Coverage frontier、plateau 偵測、bandit 演算法 |
| CoSim | Spike + Sail 主要 oracle；QEMU 為有限輔助 oracle（見 §9.1）；Soft-float 作為 FP ground truth |
| RVV（Vector）| Phase 6 獨立子專案，現階段在 Extension ADT 預留 hook |
| Shrinking | 自動縮小失敗案例到最小可重現序列 |
| Multi-core | 多 hart 場景、RVWMO litmus test |
| PMA / Cacheable | Cacheable / Uncacheable / IO memory region 的 coverage |
| Privilege 完整覆蓋 | M/S/U mode、CSR access、trap handler 生成 |
| Regression suite | 自動儲存、縮小、replay、set cover 最小化 |
| CLI | brick TUI、coverage heatmap、美觀的輸出 |
| Web App | Vue 3 + Servant、constraint editor、coverage 視覺化 |

---

## 2. 系統架構總覽

### 2.1 模組邊界

```
riscv-rig/
├── core/           ISA 模型、指令 ADT、encode/decode、CSR、PMA
├── constraint/     Constraint eDSL、SBV/Z3 integration、density estimation
├── scenario/       Scenario DSL、Phase/Event、registry、auto-discovery
├── generator/      Random + solver-directed synthesis、seed management
├── coverage/       Coverage model、bin 定義、accumulator、frontier analysis
├── cosim/          Spike/Sail/QEMU runner、diff engine、shrinking、RVWMO checker
├── optimizer/      Coverage feedback、bandit、plateau detection、test minimization
├── elf/            ELF/hex 生成、startup code、trap handler template
├── api/            Servant REST + WebSocket API
├── cli/            optparse-applicative + brick TUI
└── webapp/         Vue 3 + TypeScript + Vite（獨立 package）
```

### 2.2 資料流

```
使用者輸入
(constraints + scenarios + ext selection)
        │
        ▼
 Extension Resolver ──→ Dependency DAG 解析、補齊依賴
        │
        ▼
 Constraint Compiler ──→ SBV symbolic value → Z3 SMT query
        │
        ▼
 Generator
 ├── Solver path  ──→ Z3 找 satisfying assignment（corner case）
 └── Random path  ──→ QuickCheck/Hedgehog biased random（廣度）
        │
        ▼
 Instruction Sequence ──→ ELF/hex 生成（加上 startup + trap handler）
        │
        ▼
 CoSim Engine
 ├── Spike runner
 ├── Sail runner
 └── QEMU runner（可選）
        │
        ▼
 Diff Engine ──→ ArchState 比對 → MismatchReport
        │
     ┌──┴──┐
 [PASS]  [FAIL]
   │       │
   ▼       ▼
Coverage  Shrinking ──→ Minimal reproducing sequence
Updater         │
   │         Regression
   ▼         Storage
Coverage
Optimizer ──→ 選下一輪 extension / 調整 weights / 偵測 plateau
```

### 2.3 為什麼用 Haskell

- **ADT 完美對應 ISA**：每個指令格式是 product type，指令集是 sum type，exhaustive pattern match 是免費的 spec 檢查。
- **純函數核心**：generator、constraint compiler、coverage accumulator 都是純函數，易於測試、可重現。
- **SBV 是最成熟的 Haskell SMT binding**：直接操作 symbolic bitvector，型別安全。
- **STM（Software Transactional Memory）**：multi-core 場景的 parallel coverage accumulation 用 STM 做無鎖合併，Haskell 內建。
- **Servant**：type-safe REST API，前後端的型別定義共享，OpenAPI spec 自動生成。
- **Hedgehog**：內建 shrinking，比 QuickCheck 更現代的 property-based testing，shrinking 是本工具的核心功能。

---

## 3. 核心 ISA 模型

### 3.1 基礎型別

```haskell
-- Newtype 防止 register 搞混（type safety）
newtype Register   = Register   { unReg  :: Word5  }
newtype FPRegister = FPRegister { unFReg :: Word5  }
newtype CSRAddr    = CSRAddr    { unCSR  :: Word12 }

-- Immediate 型別（不同大小的 signed/unsigned）
newtype Imm12  = Imm12  { unImm12  :: Int12  }
newtype Imm13  = Imm13  { unImm13  :: Int13  }  -- branch offset
newtype Imm20  = Imm20  { unImm20  :: Int20  }  -- U-type
newtype Imm21  = Imm21  { unImm21  :: Int21  }  -- JAL offset
newtype UImm5  = UImm5  { unUImm5  :: Word5  }  -- shift amount

-- 已知的 zero register
x0 :: Register
x0 = Register 0
```

**設計原則**：用 newtype 而非 type alias，讓 GHC 在 compile time 阻止把 FPRegister 傳給需要 Register 的函數。型別系統本身就是一層 constraint。

### 3.2 指令格式（低層 encoding）

RISC-V 有六種指令格式，每種格式是一個 record type：

```haskell
data RFormat = RFormat
  { rFunct7 :: Word7, rRs2 :: Register, rRs1 :: Register
  , rFunct3 :: Word3, rRd  :: Register, rOpcode :: Word7 }

data IFormat = IFormat
  { iImm12  :: Imm12,  iRs1 :: Register
  , iFunct3 :: Word3,  iRd  :: Register, iOpcode :: Word7 }

data SFormat = SFormat
  { sImm12  :: Imm12,  sRs2 :: Register, sRs1 :: Register
  , sFunct3 :: Word3,  sOpcode :: Word7 }

data BFormat = BFormat
  { bImm13  :: Imm13,  bRs2 :: Register, bRs1 :: Register
  , bFunct3 :: Word3,  bOpcode :: Word7 }

data UFormat = UFormat
  { uImm20  :: Imm20,  uRd :: Register, uOpcode :: Word7 }

data JFormat = JFormat
  { jImm21  :: Imm21,  jRd :: Register, jOpcode :: Word7 }
```

### 3.3 指令 ADT（語意層）

語意層的 ADT 隱藏底層 encoding 細節，每個 constructor 直接表達指令的語意：

```haskell
data Instruction
  -- === RV64I Base ===
  -- Arithmetic
  = ADD   Register Register Register   -- rd = rs1 + rs2
  | SUB   Register Register Register
  | ADDI  Register Register Imm12      -- rd = rs1 + sext(imm)
  | ADDIW Register Register Imm12      -- 32-bit add, sign-extend to 64
  | ADDW  Register Register Register
  | SUBW  Register Register Register
  -- Logical
  | AND   Register Register Register
  | OR    Register Register Register
  | XOR   Register Register Register
  | ANDI  Register Register Imm12
  | ORI   Register Register Imm12
  | XORI  Register Register Imm12
  -- Shift
  | SLL   Register Register Register
  | SRL   Register Register Register
  | SRA   Register Register Register
  | SLLI  Register Register UImm5
  | SRLI  Register Register UImm5
  | SRAI  Register Register UImm5
  | SLLIW Register Register UImm5
  | SRLIW Register Register UImm5
  | SRAIW Register Register UImm5
  | SLLW  Register Register Register
  | SRLW  Register Register Register
  | SRAW  Register Register Register
  -- Compare
  | SLT   Register Register Register
  | SLTU  Register Register Register
  | SLTI  Register Register Imm12
  | SLTIU Register Register Imm12
  -- Upper immediate
  | LUI   Register Imm20
  | AUIPC Register Imm20
  -- Load / Store
  | LB    Register Register Imm12
  | LH    Register Register Imm12
  | LW    Register Register Imm12
  | LD    Register Register Imm12
  | LBU   Register Register Imm12
  | LHU   Register Register Imm12
  | LWU   Register Register Imm12
  | SB    Register Register Imm12
  | SH    Register Register Imm12
  | SW    Register Register Imm12
  | SD    Register Register Imm12
  -- Branch
  | BEQ   Register Register Imm13
  | BNE   Register Register Imm13
  | BLT   Register Register Imm13
  | BGE   Register Register Imm13
  | BLTU  Register Register Imm13
  | BGEU  Register Register Imm13
  -- Jump
  | JAL   Register Imm21
  | JALR  Register Register Imm12
  -- System
  | ECALL
  | EBREAK
  | FENCE FenceMode FenceMode          -- predecessor, successor
  | FENCE_I
  -- CSR
  | CSRRW  Register CSRAddr Register
  | CSRRS  Register CSRAddr Register
  | CSRRC  Register CSRAddr Register
  | CSRRWI Register CSRAddr UImm5
  | CSRRSI Register CSRAddr UImm5
  | CSRRCI Register CSRAddr UImm5

  -- === RV64M ===
  | MUL    Register Register Register
  | MULH   Register Register Register
  | MULHSU Register Register Register
  | MULHU  Register Register Register
  | DIV    Register Register Register
  | DIVU   Register Register Register
  | REM    Register Register Register
  | REMU   Register Register Register
  | MULW   Register Register Register
  | DIVW   Register Register Register
  | DIVUW  Register Register Register
  | REMW   Register Register Register
  | REMUW  Register Register Register

  -- === RV64A ===
  | LR_W      Register Register AqRl
  | SC_W      Register Register Register AqRl
  | AMOSWAP_W Register Register Register AqRl
  | AMOADD_W  Register Register Register AqRl
  | AMOAND_W  Register Register Register AqRl
  | AMOOR_W   Register Register Register AqRl
  | AMOXOR_W  Register Register Register AqRl
  | AMOMAX_W  Register Register Register AqRl
  | AMOMIN_W  Register Register Register AqRl
  | LR_D      Register Register AqRl
  | SC_D      Register Register Register AqRl
  | AMOSWAP_D Register Register Register AqRl
  | AMOADD_D  Register Register Register AqRl
  -- ... 其他 AMO 操作

  -- === RV64F ===
  | FLW    FPRegister Register Imm12
  | FSW    FPRegister Register Imm12
  | FMADD_S  FPRegister FPRegister FPRegister FPRegister RoundingMode
  | FMSUB_S  FPRegister FPRegister FPRegister FPRegister RoundingMode
  | FADD_S   FPRegister FPRegister FPRegister RoundingMode
  | FSUB_S   FPRegister FPRegister FPRegister RoundingMode
  | FMUL_S   FPRegister FPRegister FPRegister RoundingMode
  | FDIV_S   FPRegister FPRegister FPRegister RoundingMode
  | FSQRT_S  FPRegister FPRegister RoundingMode
  | FCVT_W_S  Register FPRegister RoundingMode
  | FCVT_WU_S Register FPRegister RoundingMode
  | FCVT_L_S  Register FPRegister RoundingMode
  | FCVT_LU_S Register FPRegister RoundingMode
  | FCVT_S_W  FPRegister Register RoundingMode
  | FMV_X_W   Register FPRegister
  | FMV_W_X   FPRegister Register
  -- ... FP compare, classify, sign-inject

  -- === RV64D ===
  | FLD    FPRegister Register Imm12
  | FSD    FPRegister Register Imm12
  | FADD_D   FPRegister FPRegister FPRegister RoundingMode
  | FSUB_D   FPRegister FPRegister FPRegister RoundingMode
  | FMUL_D   FPRegister FPRegister FPRegister RoundingMode
  | FDIV_D   FPRegister FPRegister FPRegister RoundingMode
  | FSQRT_D  FPRegister FPRegister RoundingMode
  | FCVT_D_S FPRegister FPRegister RoundingMode
  | FCVT_S_D FPRegister FPRegister RoundingMode
  -- ... D 版本的所有 F 指令

  -- === RV64C (Compressed，16-bit) ===
  | C_ADDI  Register Imm6
  | C_LW    Register Register Imm7
  | C_LD    Register Register Imm8
  | C_SW    Register Register Imm7
  | C_SD    Register Register Imm8
  | C_J     Imm12
  | C_BEQZ  Register Imm9
  | C_BNEZ  Register Imm9
  -- ... 完整 RVC 指令集

  -- === Privileged ===
  | MRET
  | SRET
  | URET
  | WFI
  | SFENCE_VMA Register Register
  deriving (Show, Eq, Ord, Generic)
```

**設計說明**：
- `AqRl` 是 acquire/release bit 的型別：`data AqRl = None | Release | Acquire | AcqRel`
- `RoundingMode` 是 RISC-V 的 5 種 rounding mode：`RNE | RTZ | RDN | RUP | RMM | DYN`
- `FenceMode` 是 fence 的 predecessor/successor bits：`data FenceMode = FenceMode { fI, fO, fR, fW :: Bool }`
- 每個 constructor 的參數順序遵循 RISC-V spec 的 assembly syntax 順序（rd 在前）

### 3.4 Instruction Encode / Decode

```haskell
-- 雙向轉換，是所有 binary generation 和 log parsing 的基礎
encode :: Instruction -> Word32
encode (ADD rd rs1 rs2) =
  buildRFormat 0b0110011 rd 0b000 rs1 rs2 0b0000000
encode (ADDI rd rs1 imm) =
  buildIFormat 0b0010011 rd 0b000 rs1 imm
-- ... 每個 constructor 對應精確的 encoding

decode :: Word32 -> Either DecodeError Instruction
decode word = case opcode of
  0b0110011 -> decodeRType word
  0b0010011 -> decodeIType word
  0b0000011 -> decodeLoadType word
  0b0100011 -> decodeStoreType word
  _         -> Left (UnknownOpcode opcode)
  where opcode = word .&. 0x7F

data DecodeError
  = UnknownOpcode   Word7
  | UnknownFunct3   Word7 Word3
  | UnknownFunct7   Word7 Word3 Word7
  | ReservedEncoding Word32
  | CompressedInWord32  -- 應該用 decode16
  deriving (Show, Eq)

-- RVC 的 16-bit decode
decode16 :: Word16 -> Either DecodeError Instruction
```

**為什麼 decode 回傳 Either**：RISC-V spec 有保留的 encoding，decode 到這些值應該是 `IllegalInstruction` exception，不是 Haskell exception。用 `Either` 讓 caller 明確處理這個 case。

### 3.5 CSR 模型

```haskell
-- 所有 RV64GC 的 CSR 地址
data CSR
  -- Machine Information
  = Mvendorid | Marchid | Mimpid | Mhartid
  -- Machine Trap Setup
  | Mstatus | Misa | Medeleg | Mideleg | Mie | Mtvec | Mcounteren
  -- Machine Trap Handling
  | Mscratch | Mepc | Mcause | Mtval | Mip
  -- Supervisor Trap Setup
  | Sstatus | Sedeleg | Sideleg | Sie | Stvec | Scounteren
  -- Supervisor Trap Handling
  | Sscratch | Sepc | Scause | Stval | Sip
  -- Supervisor Address Translation
  | Satp
  -- Performance Counters
  | Mcycle | Minstret | Mcycleh | Minstreth
  -- Zicntr
  | Cycle | Time | Instret
  -- PMP
  | Pmpcfg0 | Pmpcfg2 | Pmpaddr0 | Pmpaddr1  -- ... 到 Pmpaddr15
  -- Floating Point
  | Fflags | Frm | Fcsr
  deriving (Show, Eq, Ord, Enum, Bounded)

csrAddr :: CSR -> CSRAddr
csrAddr Mstatus = CSRAddr 0x300
csrAddr Misa    = CSRAddr 0x301
-- ...

-- CSR 的 access 規則：哪個 privilege level 可以讀/寫
data CSRAccess = CSRAccess
  { readPriv  :: PrivilegeLevel   -- 需要至少這個 privilege 才能讀
  , writePriv :: PrivilegeLevel   -- 需要至少這個 privilege 才能寫
  , readOnly  :: Bool             -- 部分 CSR 是 read-only（寫了要 raise IllegalInstruction）
  }

csrAccessRules :: CSR -> CSRAccess
csrAccessRules Mstatus  = CSRAccess Machine Machine False
csrAccessRules Sstatus  = CSRAccess Supervisor Supervisor False
csrAccessRules Cycle    = CSRAccess User User True  -- read-only
-- ...

-- mstatus 的完整欄位（最複雜的 CSR）
data Mstatus = Mstatus
  { mstatusSIE  :: Bool     -- Supervisor Interrupt Enable
  , mstatusMIE  :: Bool     -- Machine Interrupt Enable
  , mstatusSPIE :: Bool     -- Supervisor Previous IE
  , mstatusMPIE :: Bool     -- Machine Previous IE
  , mstatusSPP  :: PrivilegeLevel  -- Supervisor Previous Privilege
  , mstatusMPP  :: PrivilegeLevel  -- Machine Previous Privilege
  , mstatusFS   :: DirtyState      -- FP register state
  , mstatusXS   :: DirtyState
  , mstatusMXR  :: Bool     -- Make eXecutable Readable
  , mstatusSUM  :: Bool     -- Supervisor User Memory access
  , mstatusTVM  :: Bool     -- Trap Virtual Memory
  , mstatusTW   :: Bool     -- Timeout Wait (WFI)
  , mstatusTSR  :: Bool     -- Trap SRET
  }

data DirtyState = Off | Initial | Clean | Dirty
data PrivilegeLevel = User | Supervisor | Machine deriving (Eq, Ord)
```

---

## 4. 記憶體模型

### 4.1 PMA（Physical Memory Attributes）

PMA 是平台定義的、硬體固定的 physical address range 屬性。不能用軟體改變（不同於 PMP）。

```haskell
data MemoryType
  = MainMemory    -- cacheable, coherent, idempotent
  | IOMemory      -- uncacheable, non-idempotent（讀有 side effect，不能推測執行）
  | VacantMemory  -- 存取直接 raise access fault
  deriving (Show, Eq, Ord)

data CacheabilityHint = Cacheable | Uncacheable | WriteThrough
  deriving (Show, Eq)

data PMAEntry = PMAEntry
  { pmaBase        :: Word64
  , pmaSize        :: Word64
  , pmaType        :: MemoryType
  , pmaCacheable   :: CacheabilityHint
  , pmaCoherent    :: Bool       -- 多個 cache 之間是否維持 coherency
  , pmaIdempotent  :: Bool       -- 讀兩次結果相同嗎（MMIO 不行）
  , pmaExecutable  :: Bool
  , pmaReadable    :: Bool
  , pmaWritable    :: Bool
  , pmaAtomic      :: Bool       -- 支援 AMO 和 LR/SC 嗎
  }

-- 標準的記憶體布局（可被 scenario 覆寫）
defaultMemoryLayout :: MemoryLayout
defaultMemoryLayout = MemoryLayout
  { regions =
      [ PMAEntry 0x80000000 0x10000000 MainMemory Cacheable   True True True True True True
      , PMAEntry 0x10000000 0x00001000 IOMemory   Uncacheable False False False True True False -- UART
      , PMAEntry 0x02000000 0x00010000 IOMemory   Uncacheable False False False True True False -- CLINT
      ]
  , codeBase  = 0x80000000
  , dataBase  = 0x80008000
  , stackTop  = 0x80010000
  , mmioBase  = 0x10000000
  }
```

**為什麼 Cacheable / Uncacheable 重要：**

1. **LR/SC on Uncacheable**：RISC-V spec 說 LR/SC 在 non-cacheable region 的行為是 implementation-defined。很多 CPU 直接讓 SC 永遠 fail。這是一個極其重要的 corner case。
2. **AMO on IO Memory**：部分 CPU 不支援對 IO region 做 AMO，會 raise exception。這需要 coverage bin 追蹤。
3. **Speculative Access to IO**：CPU 不能對 non-idempotent memory 做推測執行（因為讀有 side effect）。這是 Spectre 類漏洞的關鍵。你的 generator 可以測試 CPU 是否正確處理這個 case。
4. **FENCE 語意**：在 cacheable 和 uncacheable 之間的 FENCE 行為不同，是 memory ordering bug 的常見來源。

### 4.2 PMP（Physical Memory Protection）

PMP 是可程式設計的 memory access control，在 Machine mode 設定，限制 Supervisor/User mode 的存取範圍：

```haskell
data PMPConfig = PMPConfig
  { pmpR     :: Bool          -- Read permission
  , pmpW     :: Bool          -- Write permission
  , pmpX     :: Bool          -- Execute permission
  , pmpA     :: PMPAddressMode
  , pmpL     :: Bool          -- Lock bit（連 Machine mode 也不能改）
  }

data PMPAddressMode
  = PMPOff    -- 不啟用
  | PMPTOP    -- 0 到 pmpaddr（含）
  | PMPNA4    -- Naturally aligned 4-byte region
  | PMPNAPOT  -- Naturally aligned power-of-2 region

-- Scenario 可以設定 PMP 來測試 access violation
data PMPScenario
  = PMPViolationLoad  -- Supervisor mode load 到沒有 R permission 的區域
  | PMPViolationStore -- 沒有 W permission 的 store
  | PMPViolationExec  -- Jump 到沒有 X permission 的區域
  | PMPLockBypass     -- Machine mode 嘗試 bypass lock bit
```

### 4.3 Page Table & Virtual Memory

Sv39（三層 page table，RV64 常用）的模型：

```haskell
data PageTableEntry = PageTableEntry
  { pteV :: Bool     -- Valid
  , pteR :: Bool     -- Read
  , pteW :: Bool     -- Write
  , pteX :: Bool     -- Execute
  , pteU :: Bool     -- User-accessible
  , pteG :: Bool     -- Global
  , pteA :: Bool     -- Accessed
  , pteD :: Bool     -- Dirty
  , ptePPN :: Word44 -- Physical Page Number
  }

data VMemScenario
  = PageFaultLoad   -- PTE.R = 0，load 觸發 page fault
  | PageFaultStore  -- PTE.W = 0，store 觸發 page fault
  | PageFaultExec   -- PTE.X = 0，fetch 觸發 instruction page fault
  | AccessedBitTest -- PTE.A = 0，觸發 accessed bit update
  | DirtyBitTest    -- PTE.D = 0，store 觸發 dirty bit update
  | HugePageAccess  -- Sv39 megapage（2MB）
  | MisalignedPage  -- Misaligned superpage PTE
  | SumBitTest      -- sstatus.SUM = 0，S-mode 存取 U-mode page
```

---

## 5. Constraint 系統

### 5.1 設計哲學

Constraint 系統的核心目標是讓使用者能夠用接近自然語言的方式描述「我想要生成什麼樣的指令」，同時底層自動呼叫 Z3 找到滿足所有 constraint 的具體值。

### 5.2 ConstraintDef 資料結構

```haskell
data ConstraintDef = ConstraintDef
  { cname        :: Text              -- 人類可讀的名稱
  , ctags        :: [Tag]             -- 分類標籤
  , cdescription :: Text              -- 詳細說明
  , cextensions  :: [Extension]       -- 需要哪些 ISA extension
  , cpredicate   :: SBVConstraint     -- 底層的 Z3 predicate
  }

-- SBVConstraint 是 SBV 的 symbolic predicate
-- 在 SBV 的 Symbolic monad 裡執行
type SBVConstraint = SymInstruction -> SBV Bool

-- Symbolic 版本的 Instruction，所有欄位都是 symbolic bitvector
data SymInstruction = SymInstruction
  { symOpcode :: SBV Word7
  , symRd     :: SBV Word5
  , symRs1    :: SBV Word5
  , symRs2    :: SBV Word5
  , symFunct3 :: SBV Word3
  , symFunct7 :: SBV Word7
  , symImm    :: SBV Int32
  }
```

### 5.3 Constraint 函數庫

**Memory Constraints：**

```haskell
-- constraints/memory/Alignment.hs
alignedAddress :: Int -> ConstraintDef
alignedAddress n = ConstraintDef
  { cname = "aligned-address-" <> show n
  , ctags = [Memory, Alignment]
  , cdescription = "Load/store address (rs1 + offset) must be " <> show n <> "-byte aligned"
  , cpredicate = \sym ->
      (sym.symRs1 + sext (sym.symImm)) `sMod` fromIntegral n .== 0
  }

naturalAlignment :: ConstraintDef  -- 對齊到指令本身要求的自然 alignment

-- constraints/memory/Ordering.hs
loadBeforeStore :: ConstraintDef   -- 確保 load 在 store 之前（序列層面）
noWriteAfterWrite :: ConstraintDef -- 避免 WAW hazard
```

**Register Constraints：**

```haskell
-- constraints/register/NoZero.hs
rdNotZero :: ConstraintDef
rdNotZero = ConstraintDef
  { cname = "rd-not-zero"
  , ctags = [Register, SafetyNet]
  , cdescription = "rd != x0, avoid writing to zero register"
  , cpredicate = \sym -> sym.symRd ./= 0
  }

rsNotZero   :: ConstraintDef  -- rs1 != x0
rs2NotZero  :: ConstraintDef  -- rs2 != x0
rdNotSameAsRs1 :: ConstraintDef  -- 避免 rd = rs1（某些 fusion 場景需要測這個）

-- constraints/register/NoDependency.hs
noLoadUseHazard :: ConstraintDef  -- 後一條指令的 rs 不等於前一條的 rd
noRAW           :: ConstraintDef  -- 更通用的 read-after-write
```

**Branch Constraints：**

```haskell
-- constraints/branch/TargetRange.hs
branchInRange :: Word64 -> Word64 -> ConstraintDef
branchForwardOnly  :: ConstraintDef  -- branch offset > 0
branchBackwardOnly :: ConstraintDef  -- branch offset < 0（loop）
branchNotSelf      :: ConstraintDef  -- 不能 branch 到自己（infinite loop）
```

**Atomic Constraints：**

```haskell
-- constraints/atomic/LrSc.hs
lrscPaired        :: ConstraintDef  -- LR 和 SC 使用同一個 address register
lrscAqRlComplete  :: ConstraintDef  -- LR.aq + SC.rl = TSO 語意
scNotAlone        :: ConstraintDef  -- SC 必須有對應的 LR 在前面

-- constraints/atomic/Ordering.hs
amoAcquire   :: ConstraintDef  -- AMO 帶 .aq
amoRelease   :: ConstraintDef  -- AMO 帶 .rl
amoAcqRel    :: ConstraintDef  -- AMO 帶 .aqrl（最強 ordering）
```

**Privilege Constraints：**

```haskell
-- constraints/privilege/CSR.hs
csrAccessible :: PrivilegeLevel -> ConstraintDef
validCsrWrite :: ConstraintDef   -- 不寫 read-only CSR
noIllegalCsrAccess :: ConstraintDef

-- constraints/privilege/Mode.hs
instrAllowedInMode :: PrivilegeLevel -> ConstraintDef
noPrivilegeEscalation :: ConstraintDef
```

### 5.4 Constraint Combinators

```haskell
-- 邏輯組合
(.&&.)    :: ConstraintDef -> ConstraintDef -> ConstraintDef
(.||.)    :: ConstraintDef -> ConstraintDef -> ConstraintDef
cnot      :: ConstraintDef -> ConstraintDef
implies   :: ConstraintDef -> ConstraintDef -> ConstraintDef

-- 條件性 constraint
whenExtension :: Extension -> ConstraintDef -> ConstraintDef
whenMode      :: PrivilegeLevel -> ConstraintDef -> ConstraintDef
whenOpcode    :: Opcode -> ConstraintDef -> ConstraintDef

-- 加權（影響 random 分佈，不影響合法性）
-- weight > 1.0 表示往這個方向多 random
-- weight < 1.0 表示少往這個方向
withWeight :: Double -> ConstraintDef -> ConstraintDef

-- ConstraintSet 操作
data ConstraintSet = ConstraintSet [ConstraintDef]

addConstraint    :: ConstraintDef -> ConstraintSet -> ConstraintSet
removeConstraint :: Text -> ConstraintSet -> ConstraintSet  -- by name
mergeConstraints :: ConstraintSet -> ConstraintSet -> ConstraintSet
listConstraints  :: ConstraintSet -> [(Text, [Tag])]

-- 操作符版本，讓 constraint 組合更易讀
myConstraints :: ConstraintSet
myConstraints = mempty
  & addConstraint alignedAddress8
  & addConstraint rdNotZero
  & addConstraint (csrAccessible Machine `implies` validTrapHandler)
  & addConstraint (whenExtension RV_A lrscPaired)
```

### 5.5 Over-constraint 偵測

**UNSAT 偵測（constraint 邏輯上不可能滿足）：**

```haskell
data FeasibilityResult
  = Feasible                    -- 有解，可以繼續
  | Infeasible [ConstraintDef]  -- UNSAT，列出衝突的 constraint 子集
  | Unknown Text                -- Z3 timeout 或 unknown

checkFeasibility :: ConstraintSet -> IO FeasibilityResult
checkFeasibility cs = do
  result <- satWith (z3 { unsatTrackingEnabled = True }) (toSBV cs)
  case result of
    Unsatisfiable -> do
      core <- getUnsatCore  -- Z3 提供最小 UNSAT core
      return $ Infeasible (lookupConstraints cs core)
    Satisfiable _ -> return Feasible
    Unknown msg   -> return $ Unknown msg
```

**Solution Density 估計（constraint 設太緊但不是 UNSAT）：**

```haskell
data Density = Density
  { sampleSize  :: Int
  , uniqueCount :: Int
  , ratio       :: Double
  , assessment  :: DensityAssessment
  }

data DensityAssessment
  = HealthyDensity          -- ratio > 0.5，解空間夠大
  | TightConstraints        -- 0.1 < ratio < 0.5，可能太緊
  | OverConstrained         -- ratio < 0.1，幾乎肯定太緊
  | PossiblyExhausted       -- 連續出現重複解，解空間可能已窮盡

estimateDensity :: ConstraintSet -> Int -> IO Density
estimateDensity cs n = do
  solutions <- collectUniqueSolutions cs n
  let uniqueRatio = fromIntegral (length solutions) / fromIntegral n
  return $ Density n (length solutions) uniqueRatio (assess uniqueRatio)
  where
    collectUniqueSolutions cs' remaining acc
      | remaining <= 0 = return acc
      | otherwise = do
          sol <- solve cs'
          case sol of
            Unsat -> return acc
            Sat s ->
              let blockingClause = cnot (exactMatch s)
              collectUniqueSolutions (addConstraint blockingClause cs') (remaining - 1) (s:acc)
```

**Constraint 放寬建議：**

當 density 低時，系統分析每個 constraint 對 density 的貢獻，提出放寬建議：

```haskell
data RelaxationSuggestion = RelaxationSuggestion
  { constraint    :: ConstraintDef
  , estimatedGain :: Double   -- 移除這個 constraint 後 density 估計增加多少
  , reason        :: Text
  }

suggestRelaxations :: ConstraintSet -> IO [RelaxationSuggestion]
```

---

## 6. Scenario 系統

### 6.1 什麼是 Scenario

Scenario 是「測試意圖」的高層描述。Constraint 描述「哪些指令合法」，Scenario 描述「要發生什麼故事」。

一個 Scenario 由多個 **Phase** 組成，每個 Phase 有自己的 ConstraintSet 和可注入的 **Event**。Solver 在每個 Phase 內解出合法的指令 binding，Generator 負責在 Phase 邊界插入 Event injection code。

### 6.2 ScenarioSpec 資料結構

```haskell
data ScenarioSpec = ScenarioSpec
  { sname        :: Text
  , stags        :: [Tag]
  , sdescription :: Text
  , sextensions  :: [Extension]       -- 需要哪些 ISA extensions（自動補齊依賴）
  , srequires    :: [ScenarioName]    -- 需要先跑哪些 scenario（可選依賴）
  , sclaims      :: [CoverageBin]     -- 這個 scenario 宣稱會覆蓋哪些 bin
  , sscenario    :: Scenario          -- 實際的 scenario 定義
  }

-- Scenario Monad：描述 phase 和 event 的序列
type Scenario = ScenarioM ()

data ScenarioM a = ScenarioM (State ScenarioState a)

-- Phase：一個有 constraint 和隨機指令的測試段落
phase :: Text -> PhaseM () -> Scenario

data PhaseM a = PhaseM
  { phaseConstraints    :: ConstraintSet
  , phaseInstructions   :: [InstrDirective]
  , phaseEvents         :: [Event]
  }

-- InstrDirective：在 phase 裡可以用的指令相關操作
data InstrDirective
  = Emit       Instruction           -- 強制插入這條指令
  | RandomN    Int Int               -- 在這個 constraint 下 random N~M 條指令
  | UseConstraint ConstraintDef      -- 在這個 phase 加一個 constraint
  | ForceValue Register Word64       -- 強制設定 register 的值（透過 CSR 或 load）
```

### 6.3 Event 系統

Event 是 scenario 的「劇情事件」，讓 CoSim 在特定時機注入外部干擾：

```haskell
data Event
  -- Interrupt injection
  = InjectTimerInterrupt              -- 設定 MTIP，下一條指令前觸發
  | InjectSoftwareInterrupt CoreID    -- 設定 MSIP
  | InjectExternalInterrupt           -- 設定 MEIP
  | InjectInterruptAfterN Int Event   -- N 條指令後才觸發

  -- Exception injection
  | ForcePageFault VAddr FaultType    -- 修改 PTE 讓下一次存取觸發 page fault
  | ForceAccessFault PAddr            -- 設定 PMP 讓下一次存取觸發 access fault
  | ForceIllegalInstruction           -- 下一條指令換成一個非法 encoding

  -- Privilege transitions
  | SetPrivilege PrivilegeLevel       -- 強制切換 privilege（透過 MRET 序列）
  | SetMstatus Mstatus                -- 設定 mstatus 的特定欄位

  -- Memory events
  | SetMemoryType PAddr MemoryType    -- 動態改變某個 region 的 cacheable 屬性
  | FlushTLB                          -- SFENCE.VMA
  | FlushCache                        -- FENCE

  -- Multi-core events
  | IPISend CoreID CoreID             -- Core A 發 IPI 給 Core B
  | CoreBarrier (Set CoreID)          -- 等所有指定 core 到達這個點

  -- Debug events
  | SetBreakpoint VAddr               -- 設定硬體 breakpoint
  | SetWatchpoint PAddr AccessType    -- 設定硬體 watchpoint
  | EnableSingleStep CoreID           -- 開啟 single-step mode
```

### 6.4 Scenario 範例

```haskell
-- scenarios/atomic/lrsc_interrupt.hs
module Scenarios.Atomic.LrscInterrupt where

spec :: ScenarioSpec
spec = ScenarioSpec
  { sname       = "lrsc-timer-interrupt"
  , stags       = [Atomic, Interrupt, Privileged, CornerCase]
  , sdescription = "LR.D/SC.D pair with a timer interrupt injected between them. \
                   \Tests whether the reservation is correctly invalidated."
  , sextensions  = [RV_A]          -- Zicsr 會自動補齊
  , srequires    = []
  , sclaims      =
      [ PatternBin LrscPair
      , PatternBin InterruptInCriticalSection
      , CrossBin (Set.singleton RV_A) LR_D
      , CrossBin (Set.singleton RV_A) SC_D
      , ValueBin Rs1 AlignedAddr
      ]
  , sscenario    = lrscInterruptScenario
  }

lrscInterruptScenario :: Scenario
lrscInterruptScenario = do
  phase "setup" $ do
    useConstraint (alignedAddress 8)  -- 8-byte aligned for LR.D
    useConstraint rdNotZero
    emit (SetPrivilege Machine)
    -- 確保 mstatus.MIE = 1（machine interrupt enabled）
    emit (SetMstatus defaultMstatus { mstatusMIE = True })

  phase "lr-acquire" $ do
    useConstraint lrscAqRlComplete
    emit (Instruction LR_D)          -- 強制產生 LR.D
    randomN 0 3                       -- 中間可以有 0~3 條不相關指令

  phase "interrupt-injection" $ do
    emit InjectTimerInterrupt         -- 注入 timer interrupt，CPU 應該跳到 trap handler

  phase "trap-handler" $ do
    useConstraint validTrapHandler
    useConstraint (instrAllowedInMode Machine)
    randomN 5 20                      -- trap handler 裡的 random 指令
    emit (Instruction MRET)           -- 從 trap handler 返回

  phase "sc-verify" $ do
    useConstraint (sameAddressReg Rs1)  -- 同一個 address register
    emit (Instruction SC_D)           -- SC.D 必須出現
    -- 注意：reservation 被 interrupt 破壞，SC.D 應該 fail（rd = 1）
    useConstraint (expectScResult ScFail)
```

### 6.5 Auto-discovery 機制

**目標**：加新的 scenario 只需要新增一個 `.hs` 檔，不需要改動任何現有程式碼。

**實作方式**：用 Cabal 的 `custom-setup` 或 `hpack` 的 pre-build hook，掃描 `scenarios/` 目錄下所有 export `spec :: ScenarioSpec` 的 module，自動生成 registry：

```haskell
-- 自動生成，不要手動編輯：src/ScenarioRegistry.hs
module ScenarioRegistry (allScenarios, findByTag, findByName) where

import qualified Scenarios.Atomic.LrscInterrupt      as S001
import qualified Scenarios.Atomic.LrscContextSwitch  as S002
import qualified Scenarios.Privilege.CsrEscalation   as S003
-- ... 自動掃描並匯入

allScenarios :: [ScenarioSpec]
allScenarios = [S001.spec, S002.spec, S003.spec, ...]

findByTag  :: Tag -> [ScenarioSpec]
findByName :: Text -> Maybe ScenarioSpec
```

**磁碟結構**：

```
scenarios/
├── atomic/           RV_A 相關
├── privilege/        M/S/U mode 相關
├── float/            RV_F/D 相關
├── memory/           Load/Store、page fault、PMA
├── compressed/       RVC 邊界 case
├── multicore/        多 hart 場景
├── debug/            Debug/trigger module
├── performance/      PMU、cycle counter
└── compliance/       對應 RISC-V spec 章節的 compliance scenario
```

### 6.6 Scenario Checker & Traceability Matrix

```haskell
data ScenarioResult = ScenarioResult
  { srSpec    :: ScenarioSpec
  , srClaimed :: Set CoverageBin    -- 宣告要測的
  , srActual  :: Set CoverageBin    -- 實際 hit 的
  , srMissed  :: Set CoverageBin    -- claimed 但沒 hit（scenario 有問題）
  , srBonus   :: Set CoverageBin    -- 沒宣告但意外 hit 的（有驚喜）
  , srUnique  :: Set CoverageBin    -- 只有這個 scenario 覆蓋（不可取代）
  , srRunTime :: NominalDiffTime
  }

-- Traceability Matrix：scenario × coverage bin
-- 回答「哪個 scenario 測了哪些 bin」
type TraceabilityMatrix = Map ScenarioName (Set CoverageBin)

buildTraceabilityMatrix :: [ScenarioResult] -> TraceabilityMatrix

-- 分析結果
findRedundantScenarios :: TraceabilityMatrix -> [(ScenarioName, ScenarioName)]
-- 找出哪些 scenario 的覆蓋完全被另一個 scenario 包含（可以考慮合併）

findEssentialScenarios :: TraceabilityMatrix -> [ScenarioName]
-- 找出哪些 scenario 有獨特的覆蓋（不能刪）

findUnclaimedBins :: [ScenarioResult] -> Set CoverageBin -> [CoverageBin]
-- 找出沒有任何 scenario 宣稱要測的 coverage bin（coverage 盲點）
```

---

## 7. Generator

### 7.1 Generator 的兩條路徑

Generator 有兩種工作模式，互補使用：

**Solver-directed path（深度）**：呼叫 Z3，在 constraint 空間的**邊界**找解。用於找 corner case。
**Random path（廣度）**：在 solver 確認的合法空間內，用 Hedgehog 做 biased random。用於廣泛探索。

```haskell
data GeneratorConfig = GeneratorConfig
  { gcConstraints   :: ConstraintSet
  , gcExtensions    :: Set Extension
  , gcSeed          :: Maybe Word64     -- Nothing = 用 system entropy
  , gcLength        :: (Int, Int)       -- 序列長度的 (min, max)
  , gcMode          :: GeneratorMode
  , gcCoverageHints :: CoverageWeight   -- 來自 optimizer 的引導
  }

data GeneratorMode
  = PureRandom                          -- 完全 random，不用 solver
  | SolverDirected Int                  -- 用 solver 找 N 個 corner case
  | Hybrid Double                       -- 0.0~1.0，solver 佔的比例
  | ScenarioMode ScenarioSpec           -- Scenario 模式
```

### 7.2 Solver-directed 生成

```haskell
generateCornerCases :: GeneratorConfig -> Int -> IO [InstrSequence]
generateCornerCases cfg n = do
  let smt = compileConstraints (gcConstraints cfg)
  solutions <- findBoundaryPoints smt n
  mapM (instantiateSequence cfg) solutions

-- 找邊界點：在解空間的「邊緣」找 solution
-- 技術上是在 constraint 的 boundary condition 加 epsilon perturbation
findBoundaryPoints :: SMTQuery -> Int -> IO [PartialAssignment]
findBoundaryPoints query n = do
  -- 1. 先找一個 satisfying assignment
  base <- solve query
  -- 2. 對每個 symbolic variable，嘗試 maximize 和 minimize
  --    Z3 的 optimize mode 可以做這件事
  boundaries <- concat <$> mapM (maximizeAndMinimize query) (variables base)
  -- 3. 取前 n 個最有趣的邊界點
  return $ take n (sortByNovelty base boundaries)
```

### 7.3 Random path（Hedgehog）

Hedgehog 比 QuickCheck 更適合本工具，原因：
- 內建 integrated shrinking（shrinking 不需要另外寫）
- 基於 `MonadGen`，更容易組合
- 支援 `Gen` 的大小參數，控制生成的「複雜度」

```haskell
genInstruction :: Set Extension -> CoverageWeight -> Gen Instruction
genInstruction exts weights = do
  -- 根據 coverage weight 選擇 opcode category
  cat <- weightedChoice weights (availableCategories exts)
  case cat of
    AluCategory    -> genAluInstruction weights
    LoadCategory   -> genLoadInstruction weights
    StoreCategory  -> genStoreInstruction weights
    BranchCategory -> genBranchInstruction weights
    AtomicCategory -> genAtomicInstruction weights
    FloatCategory  -> genFloatInstruction weights

genRegister :: Gen Register
genRegister = Register <$> Gen.word5 (Range.linear 0 31)

-- 針對 corner case 的 value generator
genCornerCaseImm12 :: Gen Imm12
genCornerCaseImm12 = Gen.frequency
  [ (3, pure (Imm12 0))          -- zero
  , (3, pure (Imm12 1))          -- one
  , (3, pure (Imm12 (-1)))       -- all ones
  , (3, pure (Imm12 2047))       -- max positive
  , (3, pure (Imm12 (-2048)))    -- min negative
  , (5, Imm12 <$> Gen.int12 (Range.linear (-2048) 2047))  -- random
  ]
```

### 7.4 Seed & Reproducibility

```haskell
data RunConfig = RunConfig
  { rcSeed   :: Seed     -- 完全確定性的 seed
  , rcConfig :: GeneratorConfig
  }

-- 每次 run 都綁定一個 seed，可以完全重現
runWithSeed :: Seed -> GeneratorConfig -> IO RunResult

-- 從 seed 派生 sub-seed（不同 component 用不同的 seed，但都源自同一個 root）
deriveSeed :: Seed -> Text -> Seed
deriveSeed rootSeed label = hashWithSalt (unSeed rootSeed) label

-- RunResult 包含 seed，發現 bug 時可以直接用這個 seed 重跑
data RunResult = RunResult
  { rrSeed       :: Seed
  , rrSequences  :: [InstrSequence]
  , rrCoverage   :: CoverageMap
  , rrMismatches :: [MismatchReport]
  }
```

### 7.5 ELF / Flat Binary 生成

Generator 產出的 `InstrSequence` 需要被包裝成真正能跑的程式：

```haskell
data TestProgram = TestProgram
  { tpStartupCode  :: [Instruction]   -- 設定 mtvec、sp、CSR 等
  , tpTrapHandler  :: [Instruction]   -- trap handler（保存/恢復 register）
  , tpTestBody     :: [Instruction]   -- 實際的測試序列
  , tpTeardown     :: [Instruction]   -- 測試結束後寫入結果到特定 address
  , tpMemoryLayout :: MemoryLayout
  }

generateELF :: TestProgram -> FilePath -> IO ()
generateFlatHex :: TestProgram -> FilePath -> IO ()

-- Startup code 模板（組合語言等價）
defaultStartup :: MemoryLayout -> [Instruction]
defaultStartup layout =
  -- csrw mtvec, trap_handler_addr
  -- la sp, stack_top
  -- csrw mstatus, 0x1888  -- 開啟 M/S/U IE
  -- j test_body

-- Trap handler 模板：保存所有 register，執行 handler，恢復並 MRET
defaultTrapHandler :: [Instruction]
```

---

## 8. Coverage 模型

### 8.1 Coverage 的哲學

Coverage 不是一個數字，是一張多維地圖。每個 dimension 對應一種「測試關心的角度」：

| Dimension | 問題 | Bin 數量 |
|---|---|---|
| Opcode | 每個指令有沒有跑過？ | ~150 |
| Format | 每種指令格式有沒有跑過？ | 6 |
| Value Range | 操作數的極端值有沒有測到？ | 8 per operand |
| Sequence Pattern | 重要的指令序列 pattern 有沒有出現？ | ~50 |
| Extension Cross | 多個 extension 同時 active 時的交叉 case？ | N×Opcode |
| Privilege | 每個 privilege level 下的行為有沒有測？ | 3×Opcode |
| Memory Type | 指令在不同 memory type（cacheable/IO）上的行為？ | 3×Opcode |
| Multi-core Race | 多 hart 的競爭情況有沒有測到？ | ~30 |

### 8.2 CoverageBin 定義

```haskell
data CoverageBin
  -- Level 1: Opcode coverage
  = OpcodeBin       Opcode                        -- 這個指令有沒有跑過

  -- Level 2: Format coverage
  | FormatBin       InstrFormat                   -- R/I/S/B/U/J 各格式

  -- Level 3: Value range coverage
  | ValueBin        Operand ValueCategory         -- 操作數的值在哪個 bucket

  -- Level 4: Cross coverage
  | OpcodeValueBin  Opcode ValueCategory          -- 指令 × 值 range
  | OpcodeModeBin   Opcode PrivilegeLevel         -- 指令 × privilege level
  | OpcodeMemBin    Opcode MemoryType             -- 指令 × memory type

  -- Level 5: Sequence pattern coverage
  | PatternBin      SequencePattern               -- 特定的指令序列 pattern

  -- Level 6: Extension cross coverage
  | ExtCrossBin     (Set Extension) Opcode        -- extension 組合 × 指令

  -- Level 7: Multi-core coverage
  | MCRaceBin       Opcode Opcode                 -- 兩個 core 的指令同時執行
  | MCOrderingBin   MemoryOrdering                -- RVWMO ordering case
  | MCCoherenceBin  CoherenceScenario

  -- Level 8: Special coverage
  | FPRoundingBin   RoundingMode FPExceptionFlag  -- FP rounding × exception
  | RVCBoundaryBin  RVCBoundaryType               -- RVC 16/32-bit 邊界
  | PrivTransBin    PrivilegeLevel PrivilegeLevel  -- privilege mode 轉換
  | CSRAccessBin    CSR AccessType PrivilegeLevel  -- CSR 存取 × mode

  -- Level 9: Spec compliance
  | SpecBin         SpecSection                   -- 對應 RISC-V spec 的哪個章節
  deriving (Show, Eq, Ord)

data ValueCategory
  = Zero         -- = 0
  | One          -- = 1
  | MaxPositive  -- = 2^(n-1) - 1（最大正值）
  | MinNegative  -- = -2^(n-1)（最小負值）
  | AllOnes      -- = -1（所有 bit 為 1）
  | SmallPos     -- 1 < x < 100
  | AlignedAddr  -- 自然對齊的地址
  | UnalignedAddr -- 未對齊的地址
  deriving (Show, Eq, Ord, Enum, Bounded)

data SequencePattern
  = LoadUseDependency      -- load 後立刻用該 register
  | BranchTaken            -- branch 跳了
  | BranchNotTaken         -- branch 沒跳
  | BackwardBranch         -- backward branch（loop）
  | ForwardBranch          -- forward branch
  | LrscPair               -- LR 後跟著 SC，同一個 address
  | LrscSuccess            -- SC 成功（rd = 0）
  | LrscFail               -- SC 失敗（rd = 1）
  | InterruptInCritical    -- interrupt 在 LR/SC 中間
  | CsrReadModifyWrite     -- CSRRS/CSRRC 的 read-modify-write pattern
  | CallReturnPair         -- JAL + JALR 的 call/return
  | TailCall               -- JAL 但 rd = x0
  | FenceBeforeAtomic      -- FENCE 在 AMO/LR/SC 之前
  | ExceptionReturn        -- MRET/SRET
  | WfiWithInterrupt       -- WFI 後收到 interrupt
  | InstructionFusion      -- LUI + ADDI（可能被 CPU fusion）
  deriving (Show, Eq, Ord, Enum, Bounded)
```

### 8.3 Coverage Map 與 Accumulator

```haskell
-- Coverage map 是從 bin 到 hit count 的映射
type CoverageMap = Map CoverageBin HitCount
type HitCount = Word64

-- Coverage Accumulator 是 concurrent 的（multi-core generation 用 STM）
data CoverageAccumulator = CoverageAccumulator
  { caMap   :: TVar CoverageMap   -- STM transactional variable
  , caTotal :: TVar Word64        -- 總執行次數
  }

-- Thread-safe 的 coverage update
recordCoverage :: CoverageAccumulator -> [CoverageBin] -> STM ()
recordCoverage acc bins = modifyTVar (caMap acc) (applyHits bins)
  where applyHits bs m = foldr (\b -> Map.insertWith (+) b 1) m bs

-- Coverage summary
data CoverageSummary = CoverageSummary
  { totalBins       :: Int
  , hitBins         :: Int
  , missingBins     :: [CoverageBin]        -- 精確列出沒 hit 的 bin
  , impossibleBins  :: [CoverageBin]        -- 結構上不可能的 bin
  , constrainedBins :: [(CoverageBin, [ConstraintDef])]  -- 被 constraint 封住的 bin
  , coveragePct     :: Double
  , byCategory      :: Map BinCategory Double  -- 每個分類的 coverage %
  }
```

### 8.4 Coverage Frontier

Coverage frontier 是「已 hit 的 bin 集合的邊界」——已 hit 但鄰居還是空的 bin。這些 bin 的鄰居是最容易覆蓋到的下一個目標。

```haskell
-- 定義 bin 之間的鄰近關係
neighbors :: CoverageBin -> [CoverageBin]
neighbors (ValueBin op Zero)     = [ValueBin op One, ValueBin op SmallPos]
neighbors (ValueBin op MaxPos)   = [ValueBin op SmallPos, ValueBin op AllOnes]
neighbors (OpcodeBin op)         = map OpcodeBin (relatedOpcodes op)
neighbors (ExtCrossBin exts op)  = 
  -- 移除一個 extension，或換成相關的 opcode
  [ExtCrossBin (Set.delete e exts) op | e <- Set.toList exts]
  ++ [ExtCrossBin exts op' | op' <- relatedOpcodes op]

-- 計算 frontier
computeFrontier :: CoverageMap -> Set CoverageBin -> Set CoverageBin
computeFrontier cmap allBins =
  Set.filter isFrontier hitBins
  where
    hitBins = Map.keysSet (Map.filter (>0) cmap)
    isFrontier bin = any (`Set.notMember` hitBins) (neighbors bin)

-- Frontier bins 的優先順序（frontier 上鄰居越多空的，優先順序越高）
frontierPriority :: CoverageMap -> Set CoverageBin -> [(CoverageBin, Int)]
frontierPriority cmap allBins =
  sortBy (comparing (negate . snd))
  [ (bin, emptyNeighborCount bin)
  | bin <- Set.toList (computeFrontier cmap allBins)
  ]
  where
    emptyNeighborCount bin =
      length [n | n <- neighbors bin, Map.findWithDefault 0 n cmap == 0]
```

### 8.5 RISC-V Spec Compliance Mapping

每個 coverage bin 可以標注它對應 RISC-V spec 的哪個章節：

```haskell
data SpecSection = SpecSection
  { volume  :: Int     -- Volume I（Unprivileged）或 Volume II（Privileged）
  , chapter :: Int
  , section :: Text    -- 例如 "8.2" for LR/SC
  , description :: Text
  }

specMapping :: CoverageBin -> Maybe SpecSection
specMapping (PatternBin LrscPair) = Just $ SpecSection 1 8 "8.2"
  "Load-Reserved/Store-Conditional Instructions"
specMapping (PatternBin LrscSuccess) = Just $ SpecSection 1 8 "8.2"
  "SC.D returns 0 in rd on success"
specMapping (MCOrderingBin StoreLoad) = Just $ SpecSection 1 17 "17.1"
  "RVWMO Memory Ordering Model"
-- ...

-- 產生 spec compliance report
generateComplianceReport :: CoverageMap -> ComplianceReport
```

---

## 9. CoSim 引擎

### 9.1 設計目標與 Oracle 能力模型

CoSim 引擎讓同一個測試序列在多個獨立實作上執行，比對每一步的 architectural state。**Spike 和 Sail 是主要 oracle**，QEMU 是有限範圍的輔助 oracle。

#### Oracle 能力宣告

每個 oracle 對不同類型的測試有不同的可信度，必須明確宣告，讓系統在配對時自動過濾：

```haskell
data CoSimOracle
  = OracleSpike     SpikePath
  | OracleSail      SailPath
  | OracleQEMU      QEMUPath     -- 有限 oracle，見下方限制
  | OracleSoftFloat              -- Pure Haskell soft-float，FP 的 ground truth
  deriving (Show, Eq)

data OracleCapabilities = OracleCapabilities
  { supportsInterruptTiming  :: Bool  -- interrupt 在特定指令後觸發的精確 timing
  , supportsFPExactSemantics :: Bool  -- IEEE 754 rounding mode + exception flag 精確語意
  , supportsRVWMO            :: Bool  -- RVWMO 弱記憶體模型建模
  , supportsPMAAttributes    :: Bool  -- Cacheable/Uncacheable/IO 行為差異
  , supportsVectorExt        :: Bool  -- RVV Vector extension
  }

oracleCapabilities :: CoSimOracle -> OracleCapabilities
oracleCapabilities (OracleSpike     _) = OracleCapabilities True  True  False True  False
oracleCapabilities (OracleSail      _) = OracleCapabilities True  True  True  True  False
oracleCapabilities (OracleQEMU      _) = OracleCapabilities False False False False False
oracleCapabilities OracleSoftFloat     = OracleCapabilities False True  False False False
```

**為什麼 QEMU 幾乎所有項目都是 False：**

| 問題 | 說明 |
|---|---|
| Interrupt timing 不準 | QEMU 以 translation block 為單位執行，interrupt 只在 block 邊界檢查，無法精確模擬「第 N 條指令執行後觸發 interrupt」 |
| FP 語意不準 | QEMU 用 host FPU 跑 guest 浮點。Rounding mode、denormal、NaN payload 取決於 host 的 FPU 設定，不是純軟體模擬 |
| RVWMO 不建模 | QEMU 底層用 host memory model（x86 是 TSO，比 RVWMO 強）。Multi-core litmus test 的結果永遠呈現 TSO 行為，用 QEMU 做 RVWMO 測試等於沒測 |
| PMA 不建模 | QEMU 不區分 cacheable/uncacheable region。LR/SC on uncacheable 的 corner case 無效 |

**QEMU 的有效用途（保留原因）：**
- 大量基本 ALU / load / store 的 sanity check（速度快）
- 非 FP、非 interrupt、非 multi-core 的序列快速驗證
- 當 Spike 和 Sail 結果不同時，QEMU 作為「非正式的第三票」輔助人工判斷方向（但不作為決定性依據）

#### Soft-float：FP 的 Ground Truth

QEMU 的 FP 不可信，Spike 和 Sail 雖然可信，但加入一個 pure Haskell soft-float 作為第三個 FP oracle，可以在不跑任何 simulator 的情況下驗證 FP 指令的結果：

```haskell
-- Pure Haskell 實作，或 binding 到 Berkeley softfloat C library
data SoftFloatResult = SoftFloatResult
  { sfValue      :: Word64         -- 結果的 bit pattern
  , sfFlags      :: FPExceptionFlags  -- NX, UF, OF, DZ, NV
  }

evalFPInstruction :: RoundingMode -> Instruction -> [Word64] -> SoftFloatResult
```

當 Spike 和 Sail 的 FP 結果不一致時，soft-float 可以精確指出哪個 oracle 的答案是錯的。

#### Oracle 選擇規則

Generator 根據 sequence 的特性，自動選擇哪些 oracle 參與比對：

```haskell
selectOracles :: InstrSequence -> [CoSimOracle] -> [CoSimOracle]
selectOracles seq allOracles =
  filter (oracleCanHandle seq) allOracles
  where
    oracleCanHandle seq oracle =
      let caps = oracleCapabilities oracle
      in  (not (hasInterruptScenario seq) || supportsInterruptTiming  caps)
       && (not (hasFPInstructions    seq) || supportsFPExactSemantics caps)
       && (not (isMultiCoreLitmus    seq) || supportsRVWMO            caps)
       && (not (usesPMAAttributes    seq) || supportsPMAAttributes    caps)

-- 結果：
-- FP sequence     → Spike + Sail + SoftFloat（QEMU 被過濾掉）
-- Interrupt seq   → Spike + Sail（QEMU 被過濾掉）
-- RVWMO litmus    → Sail only（Spike 不建模 RVWMO，用 herd7 補充）
-- Basic ALU seq   → Spike + Sail + QEMU（全部參與）
```

#### 三角比對（限 Spike + Sail + 可選第三方）

在有效的 oracle 組合內，三角比對的邏輯：
- Spike 和 Sail 不同 → 找到 bug（Spike 或 Sail 其中一個錯）
- 兩者都同意 → PASS（這是最常見的情況）
- 加入 SoftFloat / herd7 作為 tie-breaker → 精確定位是哪個 oracle 的問題

### 9.2 Architectural State

```haskell
data ArchState = ArchState
  { asPC     :: Word64
  , asGPRs   :: Vector 32 Word64      -- x0 to x31（x0 永遠是 0）
  , asFPRs   :: Vector 32 Double      -- f0 to f31
  , asCSRs   :: Map CSRAddr Word64    -- 所有 CSR
  , asMem    :: Map Word64 Word8      -- 最近存取過的 memory（sparse）
  , asPriv   :: PrivilegeLevel
  } deriving (Show, Eq)

-- Architectural state 的 diff
data StateDiff
  = PCDiff       { spikePC   :: Word64,    sailPC   :: Word64    }
  | GPRDiff      { reg       :: Register,  spikeVal :: Word64
                 ,                          sailVal  :: Word64    }
  | FPRDiff      { fpreg     :: FPRegister, spikeVal :: Double
                 ,                          sailVal  :: Double    }
  | CSRDiff      { csrAddr   :: CSRAddr,   spikeVal :: Word64
                 ,                          sailVal  :: Word64    }
  | MemDiff      { addr      :: Word64,    spikeByte :: Word8
                 ,                          sailByte  :: Word8    }
  | PrivDiff     { spikePriv :: PrivilegeLevel, sailPriv :: PrivilegeLevel }
  deriving (Show, Eq)
```

### 9.3 Batch Mode

```haskell
data BatchConfig = BatchConfig
  { bcParallelism :: Int              -- 同時跑幾個 test
  , bcOracles     :: [CoSimOracle]    -- 參與的 oracle（系統自動用 selectOracles 過濾）
  , bcTimeout     :: NominalDiffTime  -- 每個 test 的 timeout
  }

runBatch :: BatchConfig -> [TestProgram] -> IO BatchResult

data BatchResult = BatchResult
  { brPassed    :: Int
  , brFailed    :: Int
  , brTimedOut  :: Int
  , brMismatches :: [MismatchReport]
  , brCoverage  :: CoverageMap
  }

data MismatchReport = MismatchReport
  { mrSeed      :: Seed                 -- 用這個 seed 可以重現
  , mrProgram   :: TestProgram          -- 完整的測試程式
  , mrPC        :: Word64               -- mismatch 發生在哪裡
  , mrInstruction :: Instruction        -- 哪條指令觸發了 mismatch
  , mrDiffs     :: [StateDiff]          -- 具體哪些 state 不同
  , mrContext   :: [LogEntry]           -- mismatch 前 10 條指令的 log
  }
```

### 9.4 Step Mode

Step mode 逐條指令比對，用於精確定位 mismatch：

```haskell
data StepMode
  = StepAlways                    -- 每條指令都比對
  | StepOnMismatch                -- 只在 mismatch 時輸出
  | StepAroundPC Word64 Int       -- 在特定 PC 前後 N 條指令比對

runStep :: StepMode -> TestProgram -> IO StepResult

data StepResult
  = StepPass ArchState            -- 所有步驟一致
  | StepFail Step MismatchReport  -- 第 N 步發現不一致
```

### 9.5 Log Parsing

Spike 和 Sail 的 log 格式不同，需要獨立的 parser：

```haskell
-- Spike log 格式範例：
-- core   0: 0x0000000080000000 (0x00000517) auipc a0, 0x0
-- core   0: 0x0000000080000004 (0x00050513) addi a0, a0, 0
parseSpikeLog :: Text -> Either ParseError [LogEntry]

-- Sail log 格式（更詳細，包含 register dump）
parseSailLog :: Text -> Either ParseError [LogEntry]

-- QEMU log（需要 -d in_asm,cpu flag）
parseQEMULog :: Text -> Either ParseError [LogEntry]

data LogEntry = LogEntry
  { leHartID    :: Int
  , lePC        :: Word64
  , leRawInstr  :: Word32
  , leInstr     :: Instruction      -- decode 後的指令
  , leStateDelta :: StateDelta      -- 這條指令改變了哪些 state
  }

data StateDelta = StateDelta
  { sdRegWrites  :: [(Register, Word64)]
  , sdMemWrites  :: [(Word64, Word8)]
  , sdCSRWrites  :: [(CSRAddr, Word64)]
  , sdPrivChange :: Maybe PrivilegeLevel
  }
```

### 9.6 Shrinking

當 CoSim 發現 mismatch，自動把序列縮減到最小可重現序列。這是 Hedgehog 的 integrated shrinking 機制：

```haskell
-- Hedgehog 的 Gen 已經內建 shrinking，但我們需要自訂的 shrink 策略
shrinkToMinimal :: MismatchReport -> IO MismatchReport
shrinkToMinimal mr = do
  let originalSeq = mrProgram mr
  minimal <- Hedgehog.shrink isMismatch originalSeq shrinkInstrSeq
  return mr { mrProgram = minimal }
  where
    -- 縮小策略：嘗試移除每一條指令，如果 mismatch 還在就保留移除
    shrinkInstrSeq :: InstrSequence -> [InstrSequence]
    shrinkInstrSeq seq =
      -- 嘗試每個可能的子序列
      [ deleteAt i seq | i <- [0..length seq - 1] ]
      ++ [ replaceWith i simpleInstr seq | i <- [0..length seq - 1] ]
      where simpleInstr = ADDI x1 x0 (Imm12 0)  -- NOP-like

    isMismatch :: TestProgram -> IO Bool
    isMismatch prog = do
      result <- runCoSim prog
      return (hasMismatch result)
```

### 9.7 RVWMO Litmus Test 與 Checker

RISC-V 使用 RVWMO（Relaxed Memory Ordering），比 TSO 更寬鬆。Litmus test 是一類特殊的 multi-core test，用來驗證 memory ordering behavior：

```haskell
-- 自動生成 RVWMO litmus test
data LitmusTest = LitmusTest
  { ltName    :: Text
  , ltCores   :: Map CoreID [Instruction]  -- 每個 core 的序列
  , ltInitMem :: Map Word64 Word64          -- 初始 memory 狀態
  , ltOutcomes :: [LitmusOutcome]           -- 可能的合法最終狀態
  }

data LitmusOutcome
  = Allowed  (Map Register Word64) -- 這個 register state 在 RVWMO 下是合法的
  | Forbidden (Map Register Word64) -- 這個狀態在 RVWMO 下不合法

-- 典型的 RVWMO litmus test patterns
generateLitmusTests :: [LitmusTest]
generateLitmusTests =
  [ messagePassing     -- 最基本的 message passing pattern
  , storeBuffer        -- 模擬 TSO violation（RVWMO 允許，TSO 不允許）
  , loadBuffering      -- RISC-V 特有的 load buffering
  , writeAfterWrite    -- WAW ordering
  , coherence          -- Cache coherency（co）
  ]

-- 用 herd7 工具驗證 CoSim 的 execution trace 是否 RVWMO-legal
checkRVWMO :: LitmusTest -> ExecutionTrace -> IO RVWMOResult

data RVWMOResult
  = RVWMOLegal    -- trace 是 RVWMO-legal 的
  | RVWMOIllegal  -- trace 違反了 RVWMO，這是 CPU bug
  | RVWMOUnknown  -- herd7 無法確定
```

---

## 10. Coverage Optimizer

### 10.1 設計哲學

Coverage Optimizer 是一個 feedback loop，讓系統從每次 run 的結果中學習，自動調整下一輪的生成策略。不使用黑盒 AI，所有決策都是可解釋的。

```
Coverage Map
     │
     ▼
Coverage Optimizer
├── Layer 1: Reweighter      coverage-guided 加權，調整 random 分佈
├── Layer 2: Plateau Detector  偵測 coverage 停滯
├── Layer 3: Bandit Selector   選擇下一個 extension combination
└── Layer 4: Constraint Advisor  建議放寬哪個 constraint
     │
     ▼
Generator（使用新的 weights 和策略）
```

### 10.2 Coverage-guided Reweighting

最直接的 feedback loop：空的 coverage bin → 高 weight → Generator 往那裡 random。

```haskell
data CoverageWeight = CoverageWeight
  { cwOpcodeWeights    :: Map Opcode Double
  , cwValueWeights     :: Map ValueCategory Double
  , cwPatternWeights   :: Map SequencePattern Double
  , cwExtWeights       :: Map (Set Extension) Double
  }

-- 根據 coverage map 計算新的 weights
-- 空的 bin → 高 weight，已滿的 bin → 低 weight
reweightFromCoverage :: CoverageMap -> CoverageWeight
reweightFromCoverage cmap = CoverageWeight
  { cwOpcodeWeights = Map.mapWithKey calcWeight opcodeBins
  , cwValueWeights  = Map.mapWithKey calcWeight valueBins
  -- ...
  }
  where
    calcWeight bin hitCount =
      1.0 / (fromIntegral hitCount + epsilon)  -- 避免除以零
    epsilon = 0.1
```

### 10.3 Plateau Detection

Coverage plateau = 連續 N 輪 random 都沒有新的 coverage hit。

```haskell
data PlateauState
  = Growing     { consecutiveImprovements :: Int }
  | Plateau     { consecutiveStagnantRounds :: Int }
  | DeepPlateau { roundsStagnant :: Int }  -- 需要更激進的策略

detectPlateau :: [CoverageSnapshot] -> PlateauState
detectPlateau snapshots =
  let deltas = zipWith coverageDelta snapshots (tail snapshots)
      recentDeltas = take 10 (reverse deltas)
  in if all (<= 0) recentDeltas
     then if length (filter (<=0) deltas) > 50
          then DeepPlateau (length deltas)
          else Plateau (length recentDeltas)
     else Growing (length (takeWhile (>0) (reverse deltas)))

-- 當偵測到 plateau，切換策略
handlePlateau :: PlateauState -> GeneratorConfig -> IO GeneratorConfig
handlePlateau (Plateau _) cfg =
  -- 切換到 solver-directed mode，強制找 missing bins
  return cfg { gcMode = SolverDirected 10 }
handlePlateau (DeepPlateau _) cfg = do
  -- 更激進：請求 constraint relaxation suggestions
  suggestions <- suggestRelaxations (gcConstraints cfg)
  putStrLn "Coverage plateau detected. Suggested relaxations:"
  mapM_ printSuggestion suggestions
  return cfg
```

### 10.4 Multi-armed Bandit（Thompson Sampling）

問題：有多個 extension combination，每次要選哪個跑？
Thompson Sampling 的直覺：每個 arm 維護一個 Beta 分佈，代表「這個 combination 帶來新 coverage 的機率」。每次從各 arm 的 Beta 分佈抽樣，選最高的。

```haskell
data BetaDist = BetaDist
  { alpha :: Double  -- 帶來新 coverage 的次數 + 1（成功）
  , beta  :: Double  -- 沒帶來新 coverage 的次數 + 1（失敗）
  }

data BanditState = BanditState
  { arms :: Map (Set Extension) BetaDist
  }

-- 初始狀態：所有 arm 都是 Beta(1, 1)（uniform prior）
initialBandit :: Set (Set Extension) -> BanditState
initialBandit combinations = BanditState
  { arms = Map.fromSet (\_ -> BetaDist 1.0 1.0) combinations }

-- 選下一個 combination（Thompson Sampling）
selectNextCombination :: BanditState -> IO (Set Extension)
selectNextCombination bandit = do
  -- 從每個 arm 的 Beta 分佈抽一個樣本
  samples <- mapM sampleBeta (arms bandit)
  -- 選抽到最高值的 arm
  return $ fst (maximumBy (comparing snd) (Map.toList samples))

sampleBeta :: BetaDist -> IO Double
sampleBeta (BetaDist a b) = do
  -- 用 gamma distribution 抽樣 Beta distribution
  x <- sampleGamma a
  y <- sampleGamma b
  return (x / (x + y))

-- 更新 bandit state
updateBandit :: Set Extension -> CoverageDelta -> BanditState -> BanditState
updateBandit exts delta state
  | delta > 0 =  -- 有新 coverage：成功，α++
      state { arms = Map.adjust (\b -> b { alpha = alpha b + 1 }) exts (arms state) }
  | otherwise =  -- 沒有新 coverage：失敗，β++
      state { arms = Map.adjust (\b -> b { beta  = beta  b + 1 }) exts (arms state) }
```

**為什麼 Thompson Sampling 而不是 UCB**：Thompson Sampling 在 sparse reward 環境（coverage 增長慢時）表現更好，而且天然地處理 exploration/exploitation tradeoff，不需要調整超參數。

### 10.5 Test Minimization（Set Cover）

跑了 10,000 個 test 後，找最小子集讓 coverage 不降。這是 **weighted set cover** 問題。

```haskell
-- Greedy approximation（最佳近似比 ln(n)）
minimizeTestSuite :: [TestWithCoverage] -> [TestWithCoverage]
minimizeTestSuite tests = greedy (Set.fromList allBins) [] tests
  where
    greedy uncovered selected remaining
      | Set.null uncovered = selected
      | otherwise =
          -- 每次選覆蓋最多 uncovered bins 的 test
          let best = maximumBy (comparing (coverageGain uncovered)) remaining
              newUncovered = Set.difference uncovered (testCoverage best)
          in greedy newUncovered (best : selected) (filter (/= best) remaining)

    coverageGain uncovered test =
      Set.size (Set.intersection uncovered (testCoverage test))

-- 結果通常能把 10,000 個 test 縮成 100~500 個，coverage 完全不損失
```

---

## 11. Multi-core 支援

### 11.1 Multi-core 指令序列模型

```haskell
data MultiCoreProgram = MultiCoreProgram
  { mcpNumCores     :: Int
  , mcpCoreSeqs     :: Map CoreID [Instruction]
  , mcpSharedMem    :: MemoryLayout
  , mcpSyncPoints   :: [SyncPoint]
  , mcpInterleave   :: InterleaveStrategy
  }

data SyncPoint
  = Barrier       (Set CoreID)           -- 所有指定 core 到達才繼續
  | IPISend       CoreID CoreID          -- core A 送 IPI 給 core B
  | SharedLRSC    CoreID CoreID Address  -- 兩個 core 競爭同一個 LR/SC address
  | FencedStore   CoreID Address         -- 帶 fence 的 store，另一個 core 等待看到這個 store
  | ReleaseAcquire CoreID CoreID Address -- C11 release-acquire pattern

data InterleaveStrategy
  = RandomInterleave                     -- 完全 random 的執行順序
  | StressInterleave                     -- 在 race condition 最可能的地方交錯
  | ExhaustiveInterleave                 -- 窮舉所有交錯順序（小程式用）
  | WeightedInterleave (Map CoreID Double) -- 根據 weight 決定哪個 core 執行
```

### 11.2 Multi-core Coverage Bins

```haskell
data MemoryOrdering
  = StoreLoad    -- store 後 load（TSO 最弱的 ordering）
  | LoadLoad     -- load 後 load
  | StoreStore   -- store 後 store
  | LoadStore    -- load 後 store
  | ReleaseAcquire  -- release store + acquire load
  | SCRelaxed    -- SC with relaxed ordering
  | SCStrong     -- SC with AcqRel

data CoherenceScenario
  = TrueSharing         -- 兩個 core 存取同一個 address
  | FalseSharing        -- 兩個 core 存取不同 address，但在同一個 cache line
  | ProducerConsumer    -- 一個 core 寫，另一個 core 讀
  | ReadModifyWrite     -- AMO 的 read-modify-write
  | InvalidationStorm   -- 大量 cache invalidation
```

### 11.3 Multi-core Scenario 範例

```haskell
-- scenarios/multicore/shared_lrsc.hs
sharedLrscScenario :: Scenario
sharedLrscScenario = multiCoreScenario 2 $ do
  -- 兩個 core 同時嘗試用 LR/SC 拿一個 mutex
  onCore 0 $ do
    emit (Instruction LR_D) `atAddress` mutexAddr
    randomN 1 5
    emit (Instruction SC_D) `atAddress` mutexAddr

  onCore 1 $ do
    emit (Instruction LR_D) `atAddress` mutexAddr
    randomN 1 5
    emit (Instruction SC_D) `atAddress` mutexAddr

  -- 驗證：恰好只有一個 core 的 SC 成功
  verify $ exactlyOneSucceeds [core0ScResult, core1ScResult]
```

---

## 12. Privilege Level & Trap 處理

### 12.1 Privilege Level Coverage

```haskell
data PrivTransBin = PrivTransBin
  { fromMode :: PrivilegeLevel
  , toMode   :: PrivilegeLevel
  , trigger  :: PrivTransTrigger
  }

data PrivTransTrigger
  = EcallFromU    -- U-mode ECALL → S-mode 或 M-mode
  | EcallFromS    -- S-mode ECALL → M-mode
  | Interrupt     -- interrupt → M-mode 或 S-mode
  | Exception     -- exception（page fault, illegal instr 等）
  | Mret          -- MRET → 回到 MPP
  | Sret          -- SRET → 回到 SPP
```

### 12.2 Trap Handler Generation

Generator 需要能產生合法的 trap handler，讓 interrupt/exception scenario 能正常執行：

```haskell
data TrapHandlerConfig = TrapHandlerConfig
  { thcSaveRegs    :: Bool          -- 是否保存所有 register
  , thcHandleTypes :: [TrapType]    -- 要處理哪些 trap
  , thcReturnMode  :: TrapReturn    -- 處理完要怎麼返回
  }

data TrapReturn
  = ReturnToOriginal  -- MRET 回到 mepc
  | ReturnToNext      -- MRET 回到 mepc + 4（跳過觸發指令）
  | ReturnToHandler   -- 永遠在 handler 裡跑（壓力測試用）

generateTrapHandler :: TrapHandlerConfig -> [Instruction]
```

---

## 13. 特殊 Coverage 領域

### 13.1 FP Rounding Mode × Exception Flag

RISC-V FP 有 5 種 rounding mode × 5 種 exception flag，這 25 種組合是 FP 實作最常出 bug 的地方：

```haskell
data RoundingMode = RNE | RTZ | RDN | RUP | RMM | DYN
  deriving (Show, Eq, Ord, Enum, Bounded)

data FPExceptionFlag = NX | UF | OF | DZ | NV  -- 5 個 fcsr exception bits
  deriving (Show, Eq, Ord, Enum, Bounded)

data FPSpecialValue = FPZero | FPNegZero | FPInfPos | FPInfNeg
  | FPNaN | FPSNaN  -- Signaling NaN
  | FPDenormal | FPMaxNormal | FPMinNormal
  deriving (Show, Eq, Ord, Enum, Bounded)

-- 這些組合的 coverage bin 是高優先 target
fpCoverageBins :: [(RoundingMode, FPExceptionFlag, FPSpecialValue)]
fpCoverageBins =
  [ (rm, flag, val)
  | rm   <- [minBound..maxBound]
  , flag <- [minBound..maxBound]
  , val  <- [minBound..maxBound]
  ]
```

### 13.2 RVC Boundary Testing

混合 16/32-bit 指令的 PC 對齊問題：

```haskell
data RVCBoundaryType
  = Branch32To16       -- 32-bit branch target 落在 16-bit 指令的開頭
  | Branch32To32       -- 正常的 32-bit 對齊 branch
  | ExceptionAt16      -- exception 發生在 16-bit 指令中
  | ReturnTo16         -- MRET/SRET 返回到 16-bit 指令
  | CallTo16           -- JAL/JALR 跳到 16-bit 指令
  | FusionBoundary     -- 可能被 fusion 的 LUI+ADDI 跨越 cache line boundary
```

### 13.3 WFI Race Condition

```haskell
data WFIScenario
  = WFIBeforeInterrupt    -- interrupt 在 WFI 執行前已 pending，WFI 應立刻返回
  | WFIWithInterrupt      -- interrupt 在 WFI 執行後抵達（正常情況）
  | WFINoInterrupt        -- WFI 在沒有 interrupt 的情況下（測試 timeout 行為）
  | WFIWithTWBit          -- mstatus.TW = 1，WFI in S/U mode 應 raise illegal instruction
```

### 13.4 Instruction Fusion Detection

```haskell
data FusionCandidate
  = LuiAddi   Register Imm20 Imm12    -- LUI + ADDI → 32-bit immediate load
  | AuipcAddi Register Imm20 Imm12    -- AUIPC + ADDI → PC-relative address
  | LuiLoad   Register Register Imm20 Imm12  -- LUI + LOAD
  deriving (Show, Eq)

-- Generator 刻意產生這些 fusion candidate，測試 fusion 邊界 case
generateFusionCandidates :: Gen [Instruction]
generateFusionCandidates = do
  let candidate = LuiAddi x1 someImm20 someImm12
  -- 測試 fusion 候選被 interrupt 打斷的情況
  -- 測試 fusion 候選跨越 cache line 的情況
  -- 測試 fusion 候選中間夾一個 branch target 的情況
```

### 13.5 Debug / Trigger Module

```haskell
data DebugScenario
  = HardwareBreakpoint VAddr           -- 在特定 address 設 breakpoint
  | HardwareWatchpoint PAddr AccessType -- 設 watchpoint，存取觸發 debug mode
  | SingleStep CoreID                  -- 開啟 single-step，每條指令進入 debug mode
  | DebugResume                        -- 從 debug mode 用 dret 返回
  | TriggerChaining                    -- 多個 trigger 的 chain（AND/OR 組合）
```

---

## 14. Regression 管理

### 14.1 自動儲存 Mismatch

```haskell
data RegressionCase = RegressionCase
  { rcID          :: UUID
  , rcSeed        :: Seed
  , rcConstraints :: ConstraintSet    -- 當時使用的 constraint set
  , rcScenario    :: Maybe ScenarioSpec
  , rcMinimalSeq  :: InstrSequence    -- shrinking 後的最小序列
  , rcReport      :: MismatchReport
  , rcStatus      :: RegressionStatus
  , rcCreatedAt   :: UTCTime
  }

data RegressionStatus
  = Open        -- 尚未修復
  | Fixed       -- 已修復，但保留在 regression suite
  | WontFix     -- 已知問題，不修
  | Duplicate UUID  -- 與另一個 case 重複

-- Regression cases 儲存在 SQLite
saveRegressionCase :: RegressionCase -> IO ()
loadRegressionSuite :: IO [RegressionCase]
```

### 14.2 Regression 執行

```haskell
runRegressionSuite :: [RegressionCase] -> IO RegressionResult

data RegressionResult = RegressionResult
  { rrPassed    :: [RegressionCase]
  , rrFailed    :: [RegressionCase]   -- 原本 open 的 case 仍然失敗
  , rrNewFails  :: [RegressionCase]   -- 原本 fixed 的 case 又失敗了（regression！）
  }
```

### 14.3 Incremental Coverage（跨 Session）

```haskell
-- Coverage map 序列化到磁碟，跨 session 累積
saveCoverageCheckpoint :: CoverageMap -> FilePath -> IO ()
loadCoverageCheckpoint :: FilePath -> IO CoverageMap

-- 每次 run 從上次的 checkpoint 繼續
runIncrementally :: FilePath -> GeneratorConfig -> IO RunResult
```

---

## 15. 輸出格式

### 15.1 CLI 輸出

```
riscv-rig v0.1.0

Extensions: RV64GC + A (resolved: I, M, A, F, D, C, Zicsr, Zifencei)
Scenarios: 5 loaded (3 atomic, 1 privilege, 1 float)
Constraints: 12 active

[████████████████░░░░] 80% Generating...

Round 12/20
  Generated:    247 sequences
  Passed:       244 (98.8%)
  Failed:         3 (1.2%)  ← new mismatches!
  Coverage:    1,847/3,200 bins (57.7%)  +43 new this round

Coverage by category:
  Opcode      [████████████████████░░] 139/152  (91.4%)
  Value Range [████████████████░░░░░░]  31/40   (77.5%)
  Cross       [███████████░░░░░░░░░░░] 876/1200 (73.0%)
  Seq Pattern [█████████░░░░░░░░░░░░░]  23/50   (46.0%)
  Ext Cross   [████████░░░░░░░░░░░░░░]  44/96   (45.8%)
  Multi-core  [████░░░░░░░░░░░░░░░░░░]  12/60   (20.0%)

[WARN] Coverage plateau detected (8 rounds without improvement)
  Switching to solver-directed mode for missing bins...
  Top missing bins:
    ① CrossBin(SC_D, UnalignedAddr)    ← constraint 'alignedAddress' may be blocking
    ② ExtCrossBin({A,F}, FLD+LR_D)    ← never attempted this combination
    ③ PatternBin(LrscReservationLost)  ← requires interrupt + lrsc scenario

[NEW MISMATCH] Seed: 0xDEADBEEF42
  PC: 0x80000124  Instruction: SC.D x1, x2, (x3)
  Spike: x1 = 0x0000000000000000  (SC succeeded)
  Sail:  x1 = 0x0000000000000001  (SC failed)
  → Shrinking... minimal sequence: 7 instructions
  → Saved to regression/2026-05-21-001.json
```

### 15.2 Web App 視覺化（Vue 3 + ECharts）

**Coverage Heatmap（Layer 1）**：Extension pair matrix，顏色代表 coverage %，點擊進入 drill-down。

**Drill-down（Layer 2）**：選定 extension 組合的 opcode bar chart + value range heatmap + sequence pattern coverage。

**Coverage Frontier（Layer 3）**：2D scatter plot，已 covered（灰）、frontier（橙框）、uncovered（淡黃背景）。

**Constraint Editor**：Monaco editor embedded，左側寫 Haskell constraint，右側即時看 solver 解出的 sequence 和 density estimate。

**Scenario Traceability**：左側 scenario 列表，右側 coverage bin 矩陣，高亮 unique/missing/redundant。

### 15.3 Report 格式

```haskell
data ReportFormat
  = JUnitXML    FilePath   -- CI 用
  | HtmlReport  FilePath   -- 人類閱讀
  | JsonReport  FilePath   -- 程式處理
  | MarkdownReport FilePath -- PR comment 用

generateReport :: ReportFormat -> RunResult -> IO ()
```

---

## 16. Extension 相依性系統

### 16.1 Extension DAG

```haskell
data Extension
  = RV64I | RV_M | RV_A | RV_F | RV_D | RV_C
  | Zicsr | Zifencei
  | Zba | Zbb | Zbc | Zbs  -- B extension
  | Zfh                     -- half-precision FP
  | Svpbmt                  -- page-based memory types
  | Sdext | Sdtrig          -- debug
  | RV_V                    -- Vector extension（Phase 6，目前僅預留 constructor）
  deriving (Show, Eq, Ord, Enum, Bounded)

-- RV_V 的依賴（Phase 6 實作時補齊細節）
-- RVV 需要：Zve32f → RV_F，Zve64d → RV_D
-- 另有獨立的 vector CSR：vtype, vl, vstart, vxsat, vxrm, vcsr
-- 另有獨立的 vector register file：v0~v31，每個 VLEN bits 寬（VLEN 是實作定義）
-- Coverage 空間：SEW(8/16/32/64) × LMUL(1/8~8) × vl(0~VLEN/SEW×LMUL) × masked/unmasked
-- 建議在 Phase 1-5 完成後獨立立項，專門做 RVV 的 spec

extensionDeps :: Extension -> [Extension]
extensionDeps RV_F   = [Zicsr]
extensionDeps RV_D   = [RV_F]
extensionDeps Zfh    = [RV_F]
extensionDeps Svpbmt = [RV64I]
extensionDeps _      = []

resolveExtensions :: Set Extension -> Either ConflictError (Set Extension)
resolveExtensions requested =
  let allDeps = transitiveClosure extensionDeps requested
  in case findConflicts allDeps of
       []         -> Right allDeps
       conflicts  -> Left (ConflictError conflicts)
```

### 16.2 Cross-extension 解空間

```haskell
-- 交叉 extension 時額外加的 constraint
crossExtensionConstraints :: Set Extension -> [ConstraintDef]
crossExtensionConstraints exts
  | RV_A `elem` exts && RV_F `elem` exts =
      [ floatAddrUsedByAtomic     -- LR.D 的 address 之後被 FLD 用
      , atomicOnFpRegisterAlias   -- AMO 的 rd 跟 FP register alias
      ]
  | RV_M `elem` exts && RV_A `elem` exts =
      [ mulResultAsLrscAddr       -- MUL 結果作為 LR 的 address
      ]
  | otherwise = []

-- Extension 組合選擇模式
data ExtensionSelectionMode
  = FixedSet     (Set Extension)      -- 固定選這幾個
  | AllSubsets   (Set Extension)      -- 跑所有子集
  | AutoSelect                        -- 根據 bandit 自動選
```

---

## 17. CLI 設計

### 17.1 命令結構

```
riscv-rig
├── run          執行 random generation + cosim
├── generate     只生成，不跑 cosim
├── coverage     查看/分析 coverage
├── scenario     管理 scenario（list/run/check）
├── constraint   管理 constraint（list/check/test）
├── regression   regression suite 管理
├── report       生成 report
└── serve        啟動 web server
```

**riscv-rig run 參數：**

```bash
riscv-rig run \
  --ext M,A,F \             # extension（自動補依賴）
  --cross \                  # 跑所有子集
  --scenario lrsc-interrupt \ # 指定 scenario
  --rounds 100 \             # 跑幾輪
  --seed 0xDEADBEEF \        # 固定 seed（可重現）
  --cosim spike,sail \       # 使用哪些 cosim
  --coverage-gate 80 \       # coverage < 80% 時 exit 1
  --output results/ \        # 輸出目錄
  --parallel 8               # 8 個平行 worker
```

### 17.2 Brick TUI

```
┌─ riscv-rig ──────────────────────────────────────────────┐
│  Extensions: RV64GC+A    Round: 12/20    Seed: 0xDEAD    │
├──────────────────────┬───────────────────────────────────┤
│  Coverage            │  Recent Activity                  │
│  Overall: 57.7%      │  [PASS] seq_0x1234 (3ms)          │
│  ▓▓▓▓▓▓▓▓▓▓░░░░░    │  [PASS] seq_0x1235 (2ms)          │
│                      │  [FAIL] seq_0x1236 → shrinking... │
│  Opcode:  91.4%      │  [PASS] seq_0x1237 (4ms)          │
│  Value:   77.5%      │                                   │
│  Cross:   73.0%      │  Mismatches: 3                    │
│  Pattern: 46.0%      │  ① 0x80000124 SC.D mismatch       │
│  Ext:     45.8%      │  ② 0x80002048 FCVT mismatch       │
│  MC:      20.0%      │  ③ 0x80003120 AMO mismatch        │
│                      │                                   │
│  [WARN] Plateau!     │  Constraint density: 38.2%        │
│  Switching to solver │  [OK] No UNSAT detected           │
├──────────────────────┴───────────────────────────────────┤
│  [q]uit [p]ause [r]eport [c]overage [s]hrink [h]elp      │
└──────────────────────────────────────────────────────────┘
```

---

## 18. Web App 設計

### 18.1 技術棧

- **Frontend**：TypeScript + Vue 3 + Vite + Pinia + Vue Router
- **Backend**：Haskell + Servant（REST + WebSocket）
- **Visualization**：Apache ECharts（heatmap、scatter、bar、3D scatter）
- **Editor**：Monaco Editor（constraint eDSL 編輯）
- **UI Library**：Naive UI 或 Element Plus

### 18.2 Servant API 設計

```haskell
type API
  = "api" :> "v1" :>
    ( "generate"    :> ReqBody '[JSON] GenerateRequest
                    :> Post '[JSON] GenerateResponse
    :<|> "constraints" :> Get '[JSON] [ConstraintInfo]
    :<|> "constraints" :> "check"
                    :> ReqBody '[JSON] ConstraintSet
                    :> Post '[JSON] FeasibilityResult
    :<|> "coverage"  :> Get '[JSON] CoverageSummary
    :<|> "coverage"  :> "frontier"
                    :> Get '[JSON] [CoverageBin]
    :<|> "scenarios" :> Get '[JSON] [ScenarioInfo]
    :<|> "scenarios" :> Capture "name" Text
                    :> "run" :> Post '[JSON] ScenarioResult
    :<|> "cosim"    :> "run"
                    :> ReqBody '[JSON] CoSimRequest
                    :> Post '[JSON] CoSimResult
    :<|> "regression" :> Get '[JSON] [RegressionCase]
    :<|> "ws"        :> WebSocket  -- step mode 的 real-time stream
    )
```

### 18.3 頁面設計

**Dashboard**：Overall coverage summary、最近 mismatch、bandit state（哪個 extension combination 正在被探索）

**Coverage Explorer**：
- Tab 1：Extension Pair Matrix（n×n heatmap）
- Tab 2：Drill-down（選定 combination 的 opcode bar + value heatmap）
- Tab 3：Coverage Frontier（2D scatter，灰/橙/黃三色）
- Tab 4：3D scatter（opcode × value × core interaction）

**Constraint Studio**：
- 左側：Monaco Editor（寫 constraint eDSL）
- 右側上：Solver output（生成的指令序列）
- 右側下：Density gauge + UNSAT warning + relaxation suggestions

**Scenario Browser**：
- Traceability matrix
- Per-scenario coverage claim vs. actual
- Dependency graph（D3.js force-directed）

**CoSim Live**：
- Step mode 的 real-time architectural state diff
- Register file 視覺化（高亮改變的 register）
- Memory 存取視覺化

---

## 19. 專案結構與建構系統

### 19.1 Cabal 專案結構

```
riscv-rig.cabal
cabal.project
├── core/
│   └── src/Core/{ISA, CSR, PMA, Encode, Decode}.hs
├── constraint/
│   └── src/Constraint/{DSL, Solver, Density, Library/}.hs
├── scenario/
│   └── src/Scenario/{DSL, Registry, Checker}.hs
│   └── scenarios/                              ← user-contributed
├── generator/
│   └── src/Generator/{Random, Solver, ELF, Seed}.hs
├── coverage/
│   └── src/Coverage/{Model, Accumulator, Frontier, Spec}.hs
├── cosim/
│   └── src/CoSim/{Spike, Sail, QEMU, Diff, Shrink, RVWMO}.hs
├── optimizer/
│   └── src/Optimizer/{Reweight, Plateau, Bandit, Minimize}.hs
├── api/
│   └── src/API/{Server, Types, WebSocket}.hs
├── cli/
│   └── src/CLI/{Main, TUI, Options}.hs
├── webapp/
│   ├── src/
│   ├── package.json
│   └── vite.config.ts
└── test/
    └── src/Test/{Core, Constraint, Generator, Coverage}.hs
```

### 19.2 建構指令

```bash
cabal build all              # 建構所有 component
cabal test all               # 跑所有測試
cabal run riscv-rig -- run   # 執行 CLI

cd webapp && npm install && npm run dev  # 啟動 web dev server
```

---

## 20. 開發階段規劃

### Phase 1：核心基礎（~6 週）

- [ ] RV64I + RV64M 的完整 ADT（Instruction, Register, Imm）
- [ ] Encode/Decode 雙向轉換
- [ ] CSR 模型（常用 CSR）
- [ ] 基本 ConstraintDef + SBV/Z3 integration
- [ ] Constraint combinators（.&&., .||., implies）
- [ ] Hedgehog-based random generator
- [ ] Flat binary 輸出（不需要完整 ELF）
- [ ] Spike-only CoSim（batch mode）
- [ ] 基本 coverage model（opcode + value range）
- [ ] 基本 CLI（optparse-applicative，無 TUI）

### Phase 2：完整 ISA + Scenario（~4 週）

- [ ] RV64A + RV64F + RV64D + RV64C ADT
- [ ] PMA 模型（Cacheable/Uncacheable/IO）
- [ ] Scenario 系統（Phase, Event, auto-discovery）
- [ ] Extension 相依性解析
- [ ] UNSAT core 偵測 + density estimation
- [ ] Sail CoSim integration
- [ ] Shrinking
- [ ] ELF 生成 + startup/trap handler
- [ ] Privilege level coverage（M/S/U）

### Phase 3：Coverage Optimizer + Advanced（~4 週）

- [ ] Coverage frontier 計算
- [ ] Plateau detection
- [ ] Thompson Sampling bandit
- [ ] Multi-core 場景（2-core 先）
- [ ] RVWMO litmus test 生成
- [ ] FP rounding mode × exception coverage
- [ ] RVC boundary coverage
- [ ] Regression suite（SQLite）
- [ ] brick TUI

### Phase 4：Web App + Polish（~4 週）

- [ ] Servant API
- [ ] Vue 3 + ECharts coverage dashboard
- [ ] Monaco editor constraint studio
- [ ] WebSocket step mode
- [ ] Scenario traceability matrix
- [ ] Test minimization（set cover）
- [ ] QEMU CoSim（第三個 oracle）
- [ ] JUnit XML + HTML report
- [ ] Spec compliance mapping
- [ ] Incremental coverage（SQLite checkpoint）
- [ ] CI/CD 整合（GitHub Actions）

### Phase 5：進階功能（視需求）

- [ ] Debug / trigger module scenario
- [ ] Hypervisor extension（H）
- [ ] B extension（Zba, Zbb, Zbc）
- [ ] Bayesian Optimization（外部 Python service）
- [ ] PMP coverage
- [ ] Instruction fusion detection
- [ ] Seed corpus（收集已知 corner case）
- [ ] 3D coverage scatter（ECharts 3D）

### Phase 6：RVV（Vector Extension）獨立子專案

RVV 的複雜度不亞於整個 scalar 部分，需要獨立的 spec 和 implementation plan。Phase 1-5 的架構已預留 extension hook（`RV_V` constructor、Coverage bin 的 extension 維度、Generator 的 extension filter），Phase 6 在這個基礎上擴充：

- [ ] Vector register file ADT（`VRegister`，VLEN bits 寬，實作定義）
- [ ] Vector CSR ADT（`vtype`、`vl`、`vstart`、`vxsat`、`vxrm`、`vcsr`）
- [ ] `vsetvli` / `vsetivli` / `vsetvl` 指令語意（動態決定 vl）
- [ ] 完整 RVV 指令 ADT（100+ 指令，帶 SEW、LMUL、mask bit）
- [ ] Vector-specific constraint（SEW × LMUL × vl 合法組合）
- [ ] Vector coverage bins（SEW × LMUL × vl × masked/unmasked × tail/mask-agnostic）
- [ ] Vector scenario library（stripmining、reduction、permutation）
- [ ] Spike RVV CoSim（Spike 已支援）
- [ ] Sail RVV CoSim（Sail 有 RVV 模型）

---

## 附錄 A：Haskell 新手關鍵概念

這是第一個 Haskell 專案，以下是本設計中用到的核心 Haskell 特性說明：

**ADT（Algebraic Data Types）**：
- `data Instruction = ADD ... | SUB ...` 是 sum type（OR 的關係）
- `data RFormat = RFormat { ... }` 是 product type（AND 的關係）
- RISC-V 指令集本身就是一個 sum of products，ADT 是完美的表示方式

**Newtype**：
- `newtype Register = Register Word5`：型別安全的包裝，zero runtime cost
- 讓 GHC 在 compile time 阻止把 FPRegister 傳給需要 Register 的地方

**Type Classes**：
- `deriving (Show, Eq, Ord, Generic)`：自動派生常用 instance
- `Enum, Bounded`：讓 `[minBound..maxBound]` 能列出所有 value

**Monad**：
- `ScenarioM`：描述 scenario 的 DSL（State monad）
- `Gen`：Hedgehog 的 random generation monad
- `IO`：有副作用的操作（呼叫 Z3、跑 Spike）
- `STM`：Software Transactional Memory（multi-core coverage 的 thread-safe update）

**SBV 與 SMT**：
- `SBV Word64` 是一個 symbolic 64-bit integer，Z3 可以對它做推理
- `SBV Bool` 是一個 symbolic boolean，可以用來描述 constraint
- `satWith z3 someConstraint` 讓 Z3 找一個滿足 constraint 的具體值

---

## 附錄 B：關鍵設計決策記錄

| 決策 | 選擇 | 理由 |
|---|---|---|
| FP 語言 | Haskell | ADT 完美對應 ISA，SBV 是最成熟的 SMT binding，STM 讓 parallel coverage 無鎖 |
| SMT Solver | Z3 via SBV | 最強大，bitvector arithmetic 對 RISC-V register 完美適合，UNSAT core 免費 |
| Random testing | Hedgehog | Integrated shrinking，比 QuickCheck 現代 |
| Web framework | Servant | Type-safe，API 型別與 Haskell 核心共享，OpenAPI 自動生成 |
| Frontend | Vue 3 + TypeScript | 使用者偏好，Composition API 適合複雜 state |
| Visualization | ECharts | 支援 heatmap、3D scatter、性能佳 |
| Coverage storage | SQLite | 跨 session 持久化，輕量，不需要外部 DB |
| Bandit algorithm | Thompson Sampling | 不需要調超參數，sparse reward 環境表現好 |
| AI/ML | 不使用 | 可解釋性第一，Z3 + bandit + set cover 已夠用 |
| QEMU CoSim | 有限輔助 oracle | interrupt timing 不精確（block boundary 才檢查）、FP 用 host FPU 語意不準、RVWMO 不建模（用 host TSO）、PMA 不區分。適合基本 ALU sanity check，不適合 FP/interrupt/multi-core |
| FP ground truth | Pure Haskell soft-float | QEMU FP 不可信，加入 soft-float 作為第三個 FP oracle，不依賴任何 simulator，純軟體 IEEE 754 實作 |
| RVV | Phase 6 獨立子專案 | 複雜度不亞於整個 scalar，SEW×LMUL×vl×masked 的 coverage 空間巨大，需要獨立的 spec；現階段預留 `RV_V` constructor 和 extension hook |
