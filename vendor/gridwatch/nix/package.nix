{
  lib,
  stdenv,
  bun,
  bun2nix,
  rustPlatform,
  autoPatchelfHook,
  makeWrapper,
  vulkan-loader,
  libxkbcommon,
  wayland,
  xkeyboard_config,
  xorg,
  fontconfig,
  ...
}:
let
  src = ../.;
  runtimeLibs = [
    stdenv.cc.cc.lib
    vulkan-loader
    libxkbcommon
    wayland
    xkeyboard_config
    xorg.libX11
    xorg.libxcb
    xorg.libXcursor
    xorg.libXi
    xorg.libXrandr
    fontconfig
  ];
  agent = rustPlatform.buildRustPackage {
    pname = "gridwatch-agent";
    version = "0.1.0";
    src = ../agent;
    cargoLock = {
      lockFile = ../agent/Cargo.lock;
      allowBuiltinFetchGit = true;
    };
  };
in
stdenv.mkDerivation {
  pname = "gridwatch";
  version = "0.1.0";
  inherit src;

  bunDeps = bun2nix.fetchBunDeps {
    bunNix = ../bun.nix;
  };
  nativeBuildInputs = [
    bun
    bun2nix.hook
    makeWrapper
    autoPatchelfHook
  ];
  buildInputs = runtimeLibs;

  dontConfigure = true;
  # Bun --compile embeds the JavaScript bundle in a custom ELF section;
  # the generic strip phase removes it and leaves only the Bun CLI.
  dontStrip = true;

  buildPhase = ''
    runHook preBuild
    bun build --compile src/main.tsx --outfile gridwatch
    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/bin $out/libexec $out/share/applications
    # Keep the compiled app separate from the public wrapper. Wrapping
    # $out/bin/gridwatch in place would make the wrapper execute itself.
    install -Dm755 gridwatch $out/libexec/gridwatch-app
    install -Dm755 ${agent}/bin/gridwatch-agent $out/libexec/gridwatch-agent
    makeWrapper $out/libexec/gridwatch-app $out/bin/gridwatch \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs} \
      --set XKB_CONFIG_ROOT ${xkeyboard_config}/share/X11/xkb
    install -Dm644 ${src}/gridwatch.desktop $out/share/applications/gridwatch.desktop
  '';

  meta = {
    description = "Native APC UPS observatory";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
