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

方法 B（建議，I/O 速度較快）：Copy 到 WSL2 home 目錄：
```bash
cp -r /mnt/c/Users/<你的帳號>/OneDrive/Desktop/plan/riscv-rig ~/riscv-rig
cd ~/riscv-rig
```

---

## 4. 填入 Spike 的 Nix hash（只需做一次）

`nix/spike.nix` 中的 hash 欄位目前是 placeholder，需要在 WSL2 中計算真實值：

```bash
nix shell nixpkgs#nix-prefetch-github --command \
  nix-prefetch-github --rev v1.1.1 riscv-software-src riscv-isa-sim
```

將輸出 JSON 中的 `"hash"` 值（格式：`sha256-...=`）填入 `nix/spike.nix`：

```nix
hash = "sha256-<你得到的值>";
```

---

## 5. 初始化 flake.lock

```bash
nix flake update
```

這會建立 `flake.lock`，鎖定 nixpkgs 的精確 git revision。

---

## 6. 進入開發環境

```bash
nix develop
```

**第一次執行**會：
1. 下載 nixpkgs binary cache（數百 MB）
2. 編譯 Spike（~5–15 分鐘，視 CPU 速度）
3. 下載 GHC 9.4.8 與 Haskell 套件

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

## 7. 驗證 nix build

```bash
# 單獨建置 Spike
nix build .#spike
./result/bin/spike --help

# 建置 riscv-rig 執行檔（首次約 10–25 分鐘）
nix build
./result/bin/riscv-rig version
# riscv-rig 0.1.0

# 用 nix run 執行
nix run . -- version
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

A: 重新計算 hash（見步驟 4），更新 `nix/spike.nix`。

**Q: `nix build` 時出現 sbv 版本不符**

A: 在 `nix/haskell.nix` 改為：
```nix
hfinal: hprev: {
  sbv = hprev.callHackage "sbv" "10.2" {};
}
```

**Q: 在 WSL2 中 `/mnt/c` 的 I/O 很慢**

A: 將專案 copy 到 WSL2 home 目錄（`~/riscv-rig`）再操作，速度快很多。
