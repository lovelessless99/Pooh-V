# Nix 封裝設計 — riscv-rig

## 目標

在現有 riscv-rig 專案上加入 Nix Flakes 封裝，提供：

1. **`nix develop`** — 進入開發 shell（GHC 9.4.8、Cabal、Z3、Spike），之後照常用 `cabal build` / `cabal test`
2. **`nix build`** — 直接產出 `result/bin/riscv-rig` 可執行檔（callCabal2nix 驅動）
3. **`nix build .#spike`** — 單獨建置 Spike ISA simulator

環境完全 reproducible：nixpkgs revision 與 Spike git hash 均鎖在 `flake.lock`。

---

## 使用對象

Windows 用戶透過 WSL2 使用 Nix；Linux/macOS 用戶直接使用。

---

## 架構

```
riscv-rig/
├── flake.nix              # 入口：inputs / outputs（devShell + packages）
├── flake.lock             # 自動生成，鎖定所有 inputs 的 git revision
└── nix/
    ├── spike.nix          # riscv-isa-sim 自訂 derivation
    └── haskell.nix        # Haskell package set overlay（sbv 版本 override 等）
```

---

## 元件說明

### flake.nix

- **inputs**
  - `nixpkgs`: `github:NixOS/nixpkgs/nixos-24.11`（stable，reproducible）
  - `flake-utils`: `github:numtide/flake-utils`（多平台 boilerplate 縮減）

- **outputs**（透過 `flake-utils.lib.eachDefaultSystem`，支援 `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`）
  - `devShells.default`：包含以下工具
    - `haskell.packages.ghc948.ghc` — GHC 9.4.8
    - `cabal-install` — Cabal 3.10+
    - `z3` — nixpkgs 內建 Z3（4.13.x；SBV 10.2 相容）
    - `spike`（來自 `nix/spike.nix` overlay）
    - `hlint`, `cabal-fmt`（開發便利工具）
    - `shellHook`：印出版本資訊確認環境正確
  - `packages.default`：`haskellPackages.callCabal2nix "riscv-rig" ./. {}`
  - `packages.spike`：`pkgs.spike`（同 spike.nix derivation）

- **overlays.default**：將 `spike` 與 Haskell overrides 注入 pkgs

### nix/spike.nix

```nix
{ stdenv, lib, fetchFromGitHub, dtc, pkg-config }:
stdenv.mkDerivation rec {
  pname = "spike";
  version = "1.1.1";

  src = fetchFromGitHub {
    owner = "riscv-software-src";
    repo  = "riscv-isa-sim";
    rev   = "v${version}";
    hash  = "sha256-<填入後確認>";
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs       = [ dtc ];

  configurePhase = ''
    mkdir build && cd build
    ../configure --prefix=$out
  '';
  buildPhase   = "cd build && make -j$NIX_BUILD_CORES";
  installPhase = "cd build && make install";

  meta = {
    description = "RISC-V ISA Simulator";
    license     = lib.licenses.bsd3;
    platforms   = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
```

### nix/haskell.nix

提供 GHC 9.4.8 package set 的 overlay function：

```nix
hfinal: hprev: {
  # 若 nixpkgs 24.11 中 sbv < 10.2，在此覆蓋
  # sbv = hprev.callHackage "sbv" "10.2" {};
}
```

初始為空 overlay（先確認 nixpkgs 24.11 的 sbv 版本，若足夠則不需覆蓋）。

---

## 資料流

```
nix develop
  └─ nixpkgs.ghc948 + cabal-install + z3 + spike(nix/spike.nix)
        └─ 使用者在 shell 內執行 cabal build / cabal test

nix build
  └─ callCabal2nix 讀取 riscv-rig.cabal
        └─ nixpkgs Haskell package set 解析相依
              └─ GHC 9.4.8 編譯 → result/bin/riscv-rig
```

---

## Z3 版本相容性

- nixpkgs 24.11 的 z3 約為 4.13.x
- SBV 10.2 支援 Z3 4.12 ~ 4.16，故 nixpkgs 內建版本可用
- 若日後需要精確 4.16.0，在 `nix/` 加入 `z3.nix` derivation（模式同 spike.nix）

---

## 錯誤處理

| 情境 | 處理方式 |
|------|---------|
| Spike build 失敗（缺 dtc） | dtc 已列入 buildInputs，Nix 會自動提供 |
| sbv 版本不符 | nix/haskell.nix 加入 callHackage override |
| WSL2 沒有 Nix | docs/nix-setup.md 提供安裝步驟 |
| `nix build` 找不到 cabal.project | flake.nix 的 src 指向 `./.`，會帶入整個目錄 |

---

## 測試策略

- `nix develop` 後執行 `cabal test` — 所有 45 unit tests 應通過
- `nix build` 後執行 `result/bin/riscv-rig version` → 印出 `riscv-rig 0.1.0`
- `nix build .#spike` 後執行 `result/bin/spike --help` → 印出 usage

---

## Windows / WSL2 設定（docs/nix-setup.md 摘要）

1. 安裝 WSL2（Windows 11 已內建）
2. 開啟 Ubuntu 22.04 WSL2
3. 安裝 Nix（Determinate Systems installer，自動啟用 flakes）：
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
   ```
4. 在 WSL2 中 `cd` 到 riscv-rig 目錄（Windows 路徑掛載在 `/mnt/c/...`）
5. `nix develop` — 第一次需要建置 Spike（約 5–10 分鐘）

---

## 不在範圍內

- CI/CD 整合（GitHub Actions with Nix）— Phase 後期可加
- NixOS module — 不需要
- cross-compilation（RISC-V target） — 不在此次範圍
