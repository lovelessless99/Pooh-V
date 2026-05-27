# Nix 封裝實作計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 為 riscv-rig 加入 Nix Flakes 封裝，使 `nix develop` 進入含 GHC 9.4.8 / Cabal / Z3 / Spike 的 dev shell，`nix build` 直接產出 `result/bin/riscv-rig` 執行檔。

**Architecture:** `flake.nix` 作為入口，透過 overlay 注入自訂 `spike`（來自 `nix/spike.nix`）與 Haskell package set override（`nix/haskell.nix`）。Haskell 套件用 nixpkgs 的 `callCabal2nix` 讀取 `.cabal` 檔自動解析相依。

**Tech Stack:** Nix Flakes、nixpkgs nixos-24.11、flake-utils、GHC 9.4.8 (ghc948)、callCabal2nix、riscv-isa-sim v1.1.1

---

## 檔案對應

| 檔案 | 動作 | 職責 |
|------|------|------|
| `nix/spike.nix` | 新增 | riscv-isa-sim v1.1.1 derivation（autotools out-of-tree build） |
| `nix/haskell.nix` | 新增 | GHC 9.4.8 package set overlay（sbv 版本 override 入口） |
| `flake.nix` | 新增 | 入口：inputs / devShell / packages / overlay 組裝 |
| `flake.lock` | 自動生成 | 由 `nix flake update` 產生，鎖定 nixpkgs git revision |
| `docs/nix-setup.md` | 新增 | WSL2 + Nix 安裝說明（Windows 用戶） |

---

### Task 1: nix/spike.nix — Spike ISA Simulator Derivation

**Files:**
- Create: `nix/spike.nix`

**背景：** Nix derivation 的每個 phase（configurePhase / buildPhase / installPhase）都從 `$sourceRoot` 重新開始執行。因此，需在各 phase 中用 `make -C build` 指定 build 目錄，或在 configurePhase 用 subshell `(cd build && ...)` 避免 `cd` 副作用污染後續 phase。

- [ ] **Step 1: 建立 nix/spike.nix**

```nix
{ stdenv, lib, fetchFromGitHub, dtc, pkg-config }:
stdenv.mkDerivation rec {
  pname = "spike";
  version = "1.1.1";

  src = fetchFromGitHub {
    owner = "riscv-software-src";
    repo  = "riscv-isa-sim";
    rev   = "v${version}";
    # 用 Step 2 的指令取得此 hash 並填入
    hash  = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs       = [ dtc ];

  # riscv-isa-sim 需要 out-of-tree build（原始目錄執行 configure 會失敗）
  configurePhase = ''
    runHook preConfigure
    mkdir -p build
    (cd build && ../configure --prefix=$out)
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    make -C build -j$NIX_BUILD_CORES
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    make -C build install
    runHook postInstall
  '';

  meta = with lib; {
    description = "RISC-V ISA Simulator";
    homepage    = "https://github.com/riscv-software-src/riscv-isa-sim";
    license     = licenses.bsd3;
    platforms   = platforms.linux ++ platforms.darwin;
    mainProgram = "spike";
  };
}
```

- [ ] **Step 2: 取得 Spike v1.1.1 的正確 sha256 hash**

**此步驟須在 Linux（WSL2）環境執行。**

```bash
nix shell nixpkgs#nix-prefetch-github --command \
  nix-prefetch-github --rev v1.1.1 riscv-software-src riscv-isa-sim
```

輸出範例：
```json
{
  "owner": "riscv-software-src",
  "repo": "riscv-isa-sim",
  "rev": "d2ca18a24ad7d56ef0f15b0d6a8ecc4cb7584e0e",
  "hash": "sha256-abc123XYZ.....................="
}
```

將輸出的 `"hash"` 值（格式 `sha256-...=`）填入 `nix/spike.nix` 的 `hash = "...";` 欄位，**取代** `"sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="`。

- [ ] **Step 3: Commit**

```bash
git add nix/spike.nix
git commit -m "nix: add spike v1.1.1 derivation"
```

---

### Task 2: nix/haskell.nix — Haskell Package Set Overlay

**Files:**
- Create: `nix/haskell.nix`

**背景：** nixpkgs 24.11 的 ghc948 package set 已包含 sbv 10.x。初始為空 overlay；若日後需要強制特定版本，在此加入 `callHackage` override。

- [ ] **Step 1: 建立 nix/haskell.nix**

```nix
# Haskell package set overrides for ghc948.
#
# nixpkgs 24.11 provides sbv >= 10.2 so no overrides are currently needed.
# To pin a specific version, uncomment and adapt:
#
#   hfinal: hprev: {
#     sbv = hprev.callHackage "sbv" "10.2" {};
#   }
hfinal: hprev: {}
```

- [ ] **Step 2: Commit**

```bash
git add nix/haskell.nix
git commit -m "nix: add empty haskell.nix overlay"
```

---

### Task 3: flake.nix — Main Flake Entry Point

**Files:**
- Create: `flake.nix`

**背景：**
- `callCabal2nix` 使用 IFD（import-from-derivation），需在 `nixConfig` 宣告 `allow-import-from-derivation = true`。
- `overlays.default` 定義在 `eachDefaultSystem` **外部**（用 `//` 合併），因為 overlay 不是 per-system 的。
- `apps.default` 引用 let-binding `rigPkg`，避免循環引用 `self.packages.${system}`。

- [ ] **Step 1: 建立 flake.nix**

```nix
{
  description = "riscv-rig: RISC-V Random Instruction Generator with SMT constraint solving";

  nixConfig = {
    allow-import-from-derivation = "true";
  };

  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };
        hpkgs  = pkgs.haskell.packages.ghc948;
        rigPkg = hpkgs.callCabal2nix "riscv-rig" self {};
      in
      {
        # ── devShell ─────────────────────────────────────────────────────────
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            hpkgs.ghc
            cabal-install
            z3
            spike
            hpkgs.hlint
            cabal-fmt
            pkg-config
          ];
          shellHook = ''
            echo "╔══════════════════════════════════════╗"
            echo "║  riscv-rig dev environment ready      ║"
            echo "╠══════════════════════════════════════╣"
            printf "║  GHC   : %-29s ║\n" "$(ghc --numeric-version)"
            printf "║  Cabal : %-29s ║\n" "$(cabal --numeric-version)"
            printf "║  Z3    : %-29s ║\n" "$(z3 --version)"
            printf "║  Spike : %-29s ║\n" "spike available"
            echo "╚══════════════════════════════════════╝"
          '';
        };

        # ── packages ─────────────────────────────────────────────────────────
        packages = {
          default = rigPkg;
          spike   = pkgs.spike;
        };

        # ── apps（nix run .）────────────────────────────────────────────────
        apps.default = {
          type    = "app";
          program = "${rigPkg}/bin/riscv-rig";
        };
      }
    ) //
    # ── overlay（per-system 外部，注入 spike 與 Haskell overrides）─────────
    {
      overlays.default = final: prev: {
        spike = prev.callPackage ./nix/spike.nix {};

        haskell = prev.haskell // {
          packages = prev.haskell.packages // {
            ghc948 = prev.haskell.packages.ghc948.override {
              overrides = import ./nix/haskell.nix;
            };
          };
        };
      };
    };
}
```

- [ ] **Step 2: 初始化 flake.lock（在 WSL2 執行）**

```bash
nix flake update
```

預期輸出（第一次執行）：
```
warning: creating lock file '/path/to/riscv-rig/flake.lock'
• Updated input 'flake-utils': ...
• Updated input 'nixpkgs': ...
```

這會建立 `flake.lock`，鎖定 nixpkgs 的精確 git commit。

- [ ] **Step 3: 驗證 flake 結構合法（在 WSL2 執行）**

```bash
nix flake check --no-build
```

預期：無 error 輸出（warning 可忽略）。

常見錯誤處理：
- `error: allow-import-from-derivation`：在 `~/.config/nix/nix.conf` 加入 `allow-import-from-derivation = true`
- `error: 'spike' is not a package`：確認 nix/spike.nix 的 hash 已正確填入（非 placeholder）

- [ ] **Step 4: Commit**

```bash
git add flake.nix flake.lock
git commit -m "nix: add flake.nix with devShell, packages, and overlay"
```

---

### Task 4: 驗證 nix build .#spike（Spike 可建置）

**⚠️ 此 Task 須在 WSL2 (Linux) 環境執行。Windows 原生環境不支援 Nix。**

- [ ] **Step 1: 建置 Spike**

```bash
nix build .#spike --show-trace
```

第一次執行約需 **5–15 分鐘**（下載 riscv-isa-sim 原始碼 + 編譯 C++）。

預期：建置完成，無錯誤，產生 `./result` symlink。

若失敗且錯誤訊息包含 `hash mismatch`：返回 Task 1 Step 2，重新取得正確 hash。

- [ ] **Step 2: 確認 Spike 執行檔存在**

```bash
./result/bin/spike --help 2>&1 | head -3
```

預期輸出（前三行）：
```
Spike RISC-V ISA Simulator
usage: spike [host options] <target program> [target options]
...
```

- [ ] **Step 3: Commit（若 spike.nix 有修正則加入）**

```bash
git add nix/spike.nix  # 若 hash 有更正
git commit -m "nix: verify spike build" --allow-empty
```

---

### Task 5: 驗證 nix develop 與 nix build（riscv-rig）

**⚠️ 此 Task 須在 WSL2 (Linux) 環境執行。**

- [ ] **Step 1: 確認 devShell 工具版本**

```bash
nix develop --command bash -c "
  echo '=== Tool versions ==='
  ghc --numeric-version
  cabal --numeric-version
  z3 --version
  spike --help 2>&1 | head -1
"
```

預期輸出：
```
=== Tool versions ===
9.4.8
3.10.x.x   (或更新)
Z3 version 4.x.x
Spike RISC-V ISA Simulator (或 usage: spike ...)
```

GHC **必須**為 `9.4.8`。若顯示其他版本，檢查 overlay 是否正確套用 ghc948。

- [ ] **Step 2: 在 devShell 內執行所有 unit tests**

```bash
nix develop --command bash -c "cabal test riscv-rig-test --test-show-details=direct 2>&1"
```

預期輸出（最後幾行）：
```
All 45 tests passed (0.15s)
```

若 sbv 相關測試失敗並出現 `version mismatch`，在 `nix/haskell.nix` 加入：
```nix
hfinal: hprev: {
  sbv = hprev.callHackage "sbv" "10.2" {};
}
```
然後重跑此步驟。

- [ ] **Step 3: nix build 產出執行檔**

```bash
nix build --show-trace 2>&1 | tail -5
```

第一次執行約需 **10–25 分鐘**（下載並編譯全部 Haskell 相依套件）。

預期：建置成功，無 error。

- [ ] **Step 4: 確認執行檔功能正常**

```bash
./result/bin/riscv-rig version
```

預期輸出：
```
riscv-rig 0.1.0
```

- [ ] **Step 5: 確認 nix run 也能用**

```bash
nix run . -- version
```

預期輸出：
```
riscv-rig 0.1.0
```

- [ ] **Step 6: Commit（若 haskell.nix 有修正則加入）**

```bash
git add nix/haskell.nix  # 若有加 override
git commit -m "nix: verify devShell and nix build" --allow-empty
```

---

### Task 6: docs/nix-setup.md — Windows/WSL2 安裝說明

**Files:**
- Create: `docs/nix-setup.md`

- [ ] **Step 1: 建立 docs/nix-setup.md**

```markdown
# riscv-rig Nix 環境設定指南（Windows + WSL2）

本文件說明如何在 Windows 上透過 WSL2 使用 riscv-rig 的 Nix 封裝環境。

---

## 前置需求

- Windows 10 Build 2004 或 Windows 11（已內建 WSL2 支援）

---

## 1. 安裝 WSL2 + Ubuntu 22.04

在 **PowerShell（系統管理員）** 中執行：

```powershell
wsl --install -d Ubuntu-22.04
```

安裝完成後重開機，依提示設定 Ubuntu 帳號與密碼。

確認 WSL 版本：
```powershell
wsl -l -v
# 應顯示 VERSION 2
```

---

## 2. 安裝 Nix（Determinate Systems installer）

開啟 **WSL2 Ubuntu 終端機**，執行：

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
  | sh -s -- install
```

安裝完成後**重新開啟終端機**，確認：

```bash
nix --version
# nix (Nix) 2.x.x
```

> Determinate Systems installer 預設啟用 Nix Flakes 與 `nix-command`，不需額外設定。

---

## 3. 取得專案原始碼

方法 A：直接使用 Windows 的檔案（路徑掛載在 `/mnt/c`）：
```bash
cd /mnt/c/Users/<你的帳號>/OneDrive/Desktop/plan/riscv-rig
```

方法 B（建議，I/O 速度較快）：Clone 到 WSL2 home 目錄：
```bash
cp -r /mnt/c/Users/<你的帳號>/OneDrive/Desktop/plan/riscv-rig ~/riscv-rig
cd ~/riscv-rig
```

---

## 4. 進入開發環境

```bash
nix develop
```

**第一次執行**會：
1. 下載 nixpkgs binary cache（~數百 MB）
2. 編譯 Spike（~5–15 分鐘，視 CPU 速度）
3. 下載 GHC 9.4.8 與 Haskell 套件 binary cache

進入 shell 後看到：
```
╔══════════════════════════════════════╗
║  riscv-rig dev environment ready      ║
╠══════════════════════════════════════╣
║  GHC   : 9.4.8                        ║
║  Cabal : 3.10.x.x                     ║
║  Z3    : Z3 version 4.x.x             ║
║  Spike : spike available              ║
╚══════════════════════════════════════╝
```

之後即可使用標準 Cabal 工作流：
```bash
cabal build
cabal test
cabal run riscv-rig -- generate --count 5
```

---

## 5. 直接建置執行檔

```bash
nix build
./result/bin/riscv-rig version
# riscv-rig 0.1.0

nix run . -- generate --count 3
```

---

## 6. 單獨建置 Spike

```bash
nix build .#spike
./result/bin/spike --help
```

---

## 常見問題

**Q: `nix flake check` 出現 `allow-import-from-derivation` 錯誤**

A: 在 `~/.config/nix/nix.conf` 加入一行：
```
allow-import-from-derivation = true
```
然後重試。

**Q: Spike build 失敗，顯示 `hash mismatch`**

A: nix/spike.nix 中的 hash 需重新計算：
```bash
nix shell nixpkgs#nix-prefetch-github --command \
  nix-prefetch-github --rev v1.1.1 riscv-software-src riscv-isa-sim
```
將輸出的 `"hash"` 填入 `nix/spike.nix`。

**Q: `nix build` 時出現 sbv 版本不符**

A: 在 `nix/haskell.nix` 改為：
```nix
hfinal: hprev: {
  sbv = hprev.callHackage "sbv" "10.2" {};
}
```

**Q: 在 WSL2 中 `/mnt/c` 的 I/O 很慢**

A: 把專案 copy 到 WSL2 home 目錄（`~/riscv-rig`）再操作，速度會快很多。
```

- [ ] **Step 2: Commit**

```bash
git add docs/nix-setup.md
git commit -m "docs: add WSL2 + Nix setup guide"
```

---

## Spec 覆蓋審查

| Spec 要求 | 對應 Task |
|-----------|-----------|
| `nix develop` 含 GHC 9.4.8 + Cabal + Z3 + Spike | Task 3 (devShells.default) + Task 5 Step 1 |
| `nix build` 產出 result/bin/riscv-rig | Task 3 (packages.default) + Task 5 Step 3-4 |
| `nix build .#spike` | Task 1 (spike.nix) + Task 4 |
| Spike 自訂 derivation（hash 鎖定） | Task 1 |
| flake.lock 鎖定 nixpkgs revision | Task 3 Step 2 |
| Haskell overlay（sbv override 入口） | Task 2 |
| hlint + cabal-fmt 在 devShell | Task 3 Step 1 |
| shellHook 印出版本確認 | Task 3 Step 1 |
| WSL2 setup docs | Task 6 |
| `nix run . -- version` | Task 5 Step 5 |
