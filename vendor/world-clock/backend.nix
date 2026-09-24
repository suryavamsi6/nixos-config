{ pkgs }:
pkgs.rustPlatform.buildRustPackage {
  pname = "serpantinum-world-clock-backend";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;
  doCheck = true;
  meta = {
    description = "DST-aware time and city-search helper for Serpantinum World Clock";
    license = pkgs.lib.licenses.mit;
    platforms = pkgs.lib.platforms.linux;
    mainProgram = "serpantinum-world-clock-backend";
  };
}
