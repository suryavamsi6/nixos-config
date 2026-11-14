# OpenAI Codex CLI (github:openai/codex) -- the Rust coding agent that
# MonoCode and the terminal harnesses drive.
#
# Packaged from the official musl codex-package bundle rather than the bare
# codex binary: the CLI's command runner spawns `codex-code-mode-host` as an
# executable sibling and resolves `codex-path/rg` and `codex-resources/bwrap`
# from the package root (the parent of the executable holding
# codex-package.json), and those ship only in the bundle. All binaries are
# static-pie musl, so they run on NixOS unpatched.
#
# The tree must stay intact under share/codex-package and $out/bin/codex is
# a wrapper, not a symlink: the CLI resolves its package relative to its own
# executable path. Release tags carry a rust-v prefix, which the update-pins
# entry strips via tag_prefix, so codexVersion is the bare semver and the
# URL adds it back. Bump codexVersion and the hash together, or run
# `nix run .#update-pins`.
{ lib, ... }:
{
  options.flake.modules.homeManager.codex = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      let
        codexVersion = "0.169.0";
        codex = pkgs.stdenvNoCC.mkDerivation {
          pname = "codex";
          version = codexVersion;

          nativeBuildInputs = [ pkgs.makeWrapper ];

          src = pkgs.fetchurl {
            url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-package-x86_64-unknown-linux-musl.tar.gz";
            hash = "sha256-O47QkRScxjpZBGufCUvPohzbTdoV7eRBzjabzuSnG6A=";
          };

          sourceRoot = ".";

          installPhase = ''
            runHook preInstall
            mkdir -p $out/share/codex-package $out/bin
            cp -r . $out/share/codex-package/
            # stdenv leaves its dumped environment in the build directory.
            rm -f $out/share/codex-package/env-vars
            makeWrapper $out/share/codex-package/bin/codex $out/bin/codex
            runHook postInstall
          '';

          meta = {
            description = "OpenAI's coding agent CLI";
            homepage = "https://github.com/openai/codex";
            changelog = "https://github.com/openai/codex/releases/tag/rust-v${codexVersion}";
            license = lib.licenses.asl20;
            sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
            platforms = [ "x86_64-linux" ];
            mainProgram = "codex";
          };
        };
      in
      {
        home.packages = [ codex ];
      };
  };
}
