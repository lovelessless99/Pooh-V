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

        # ── apps (nix run .) ──────────────────────────────────────────────────
        apps.default = {
          type    = "app";
          program = "${rigPkg}/bin/riscv-rig";
        };
      }
    ) //
    # ── overlay (not per-system; injected into pkgs via overlays list above) ─
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
