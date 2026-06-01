{ stdenv, lib, fetchFromGitHub, dtc, pkg-config }:
stdenv.mkDerivation rec {
  pname = "spike";
  version = "1.1.1";

  src = fetchFromGitHub {
    owner = "riscv-software-src";
    repo  = "riscv-isa-sim";
    rev   = "v${version}";
    # Run this in WSL2 to get the real hash:
    #   nix shell nixpkgs#nix-prefetch-github --command \
    #     nix-prefetch-github --rev v1.1.1 riscv-software-src riscv-isa-sim
    # Then replace the hash below with the "hash" field from the output.
    hash  = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs       = [ dtc ];

  # riscv-isa-sim requires an out-of-tree build.
  # Each Nix phase starts fresh from $sourceRoot, so we use:
  #   - subshell (cd build && ...) in configurePhase to avoid cwd side-effects
  #   - make -C build in later phases
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
