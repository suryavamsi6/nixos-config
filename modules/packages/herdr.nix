# Herdr desktop app (herdr.dev) and the runtime it drives the terminals with.
#
# Upstream ships no Nix packaging: the app is a prebuilt Rust/GPUI binary in a
# release tarball, and herdr-core (`hc`, the background server that owns the
# terminals) is a second, separate static-pie binary. Both are pinned here.
#
# Two things shape this module:
#
#   * The app finds herdr-core itself: PATH first, then ~/.nix-profile/bin and
#     /run/current-system/sw/bin. Home Manager puts both packages in the
#     profile, so no `core` setting in ~/.config/herdr-app/settings.json is
#     needed. herdr-core reads its own /nix/store path and reports itself as
#     Nix-managed, so `hc update` and the app's "Update herdr-core" button both
#     refuse and point back here instead of swapping the binary under Nix.
#   * The app self-updates by renaming its own install folder. A store path is
#     immutable, so that swap fails and the pinned version stands; Nix owns the
#     bump (`nix run .#update-pins -- --only herdr-app,herdr-core`). The failed
#     check is logged and retried every 30 minutes, nothing more.
#
# The binary loads its graphics stack at runtime (dlopen) instead of linking it,
# so libvulkan/libEGL/libwayland-client have to reach it through
# LD_LIBRARY_PATH; the X11 and keyboard libraries it does link against are
# patched by autoPatchelfHook.
{ lib, ... }:
{
  options.flake.modules.homeManager.herdr = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, lib, ... }:
      let
        herdrAppVersion = "0.1.9";
        herdr-app = pkgs.stdenv.mkDerivation {
          pname = "herdr-app";
          version = herdrAppVersion;

          src = pkgs.fetchurl {
            url = "https://releases.herdr.dev/app/${herdrAppVersion}/herdr-app-linux-x86_64.tar.gz";
            hash = "sha256-2m97QPbEFsW03vjbz4t2Z30Cvk9LRdBqTWWHZoUOC0U=";
          };

          nativeBuildInputs = [
            pkgs.autoPatchelfHook
            pkgs.makeWrapper
          ];
          buildInputs = [
            pkgs.libxcb
            pkgs.libxkbcommon
            pkgs.stdenv.cc.cc.lib
          ];

          dontStrip = true;

          # The default unpackPhase already cds into the tarball's single
          # `herdr-app/` folder, so that folder is copied over as-is: the app
          # treats the folder holding its executable as its install root
          # (src/update.rs) and reads its icon and notices from beside it.
          installPhase = ''
            runHook preInstall
            mkdir -p $out/lib/herdr-app
            cp -a ./. $out/lib/herdr-app/
            chmod 755 $out/lib/herdr-app/herdr-app

            makeWrapper $out/lib/herdr-app/herdr-app $out/bin/herdr-app \
              --suffix LD_LIBRARY_PATH : ${
                lib.makeLibraryPath [
                  pkgs.vulkan-loader
                  pkgs.libglvnd
                  pkgs.wayland
                ]
              }

            install -Dm444 herdr-app.svg \
              $out/share/icons/hicolor/scalable/apps/herdr-app.svg
            install -Dm444 ${./herdr-app.desktop} $out/share/applications/herdr-app.desktop
            runHook postInstall
          '';

          meta = {
            description = "Native desktop app for terminals and coding agents that keep running";
            homepage = "https://herdr.dev/";
            changelog = "https://github.com/herdrdev/herdr-app";
            license = lib.licenses.asl20;
            sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
            platforms = [ "x86_64-linux" ];
            mainProgram = "herdr-app";
          };
        };

        herdrCoreVersion = "0.1.14";

        herdr-core = pkgs.stdenv.mkDerivation {
          pname = "herdr-core";
          version = herdrCoreVersion;

          src = pkgs.fetchurl {
            url = "https://releases.herdr.dev/core/${herdrCoreVersion}/herdr-core-linux-x86_64.tar.gz";
            hash = "sha256-6dur3q0M4M495RtvVMyVSe/tu0Gy+ESLaTKrDRRCND4=";
          };

          # The tarball is the bare binary and no directory, which the default
          # unpackPhase rejects, so it is unpacked here.
          unpackPhase = "tar -xzf $src";
          sourceRoot = ".";

          # Static-pie: nothing to patch, nothing worth stripping.
          dontStrip = true;

          installPhase = ''
            runHook preInstall
            install -Dm755 herdr-core $out/bin/herdr-core
            ln -s herdr-core $out/bin/hc
            runHook postInstall
          '';

          meta = {
            description = "Background server that runs the terminals and agents Herdr shows";
            homepage = "https://herdr.dev/core/";
            license = lib.licenses.asl20;
            sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
            platforms = [ "x86_64-linux" ];
            mainProgram = "herdr-core";
          };
        };
        # The 0oz design theme/layout suite (github.com/0OZ/0oz-design): a
        # layout, a theme, and seven `oz-*` mods. All four install folders sit
        # beside the app's own state in ~/.config/herdr-app. Herdr's SVG asset
        # loader cannot read symlinks, so activation materializes managed SVGs.
        # Home Manager still pins the source files and other mod assets.
        #
        # `oz-pet` and the `insights` / `automations` / `atuin-threads` panels
        # are not upstream. `oz-pet` is this repo's own mod (./herdr-oz-pet);
        # `automations` and `atuin-threads` are the panels of
        # github.com/DnzzL/herdr-automations and github.com/atuinsh/herdr-atuin-threads,
        # copied into ./herdr-files because upstream ships them as app mods, not Nix
        # packages; `insights` comes from github.com/GaganSD/coding-agent-toolkit.
        # All are appended to the layout below, and ./herdr-files/mods/oz-tabs
        # is upstream's tab bar with a button for each. The layout is patched at build
        # time instead of forked, so bumping the upstream rev keeps all of it.
        oz-design = pkgs.fetchFromGitHub {
          owner = "0OZ";
          repo = "0oz-design";
          rev = "858f987bfe18c8d31379251f709fe009b8373125";
          hash = "sha256-/5+Om96TWdP58Tn8MCAYvebvire/aKhKhV0oZOFP23M=";
        };

        # The empty pet float launches a frameless window that stays where
        # dragged; automations/threads/insights are extra children of the
        # `panel-body` stack, opened by their tab-bar buttons.
        # `..|objects|select(...)|= ...` mutates the node in place; a plain
        # `.children[] | select(...)` would make that node the whole output.
        layoutPatched = pkgs.runCommand "0oz-design-patched.json" { nativeBuildInputs = [ pkgs.jq ]; } ''
          jq '
            .floating = ((.floating // []) + [{
              id: "oz-pet", content: { mod: "oz-pet" }, edge: "bottom", align: "end"
            }])
            | (.. | objects | select(.id? == "sidebar-footer")) |= (.size.px = 164)
            | (.. | objects | select(.id? == "panel-body")) |= (.children += [
                { id: "automations", type: "block", content: { mod: "automations" } },
                { id: "atuin-threads", type: "block", content: { mod: "atuin-threads" } },
                { id: "insights", type: "block", content: { mod: "insights" } }
              ])' ${oz-design}/layouts/0oz-design.json > $out
        '';

        # Token-usage dashboard over local Pi/Codex/Claude/OpenCode sessions.
        # It ships `place: none` and runs its collector through `node`, which is
        # not on a Herdr-launched process' PATH, so the path is pinned into the
        # `runtime.json` the mod reads (falling back to "node" when absent).
        # Only the mod folder is taken: upstream's npm installer records its own
        # ownership and refuses a Home Manager-managed tree.
        herdrInsightsSrc = pkgs.fetchFromGitHub {
          owner = "GaganSD";
          repo = "coding-agent-toolkit";
          rev = "92cdb30bfe5b41b0b25e5a44f2b3965f9811ce24";
          hash = "sha256-bTcaOhKZhOdbGdUnK6Mp17DktyqZoZjaCSjrgCxdtQQ=";
        };
        herdrInsights =
          # The upstream mod folder is 555, so the copy lands read-only and
          # runtime.json cannot be written until the mode is relaxed.
          pkgs.runCommand "herdr-insights-mod" { } ''
            mkdir -p $out
            cp -a ${herdrInsightsSrc}/herdr-insights/mods/insights/. $out/
            chmod -R u+w $out
            printf '%s\n' '{"node":"${pkgs.nodejs_22}/bin/node"}' > $out/runtime.json
          '';
      in
      {
        home.packages = [
          herdr-app
          herdr-core
          # The herdr-opencode-usage mod shells out to `sqlite3` to read
          # opencode.db; Herdr-launched processes get the login PATH, which
          # has no sqlite3 without this.
          pkgs.sqlite
        ];

        # One attribute set: `xdg.configFile` cannot be assigned twice.
        xdg.configFile = {
          "herdr-app/layouts/0oz-design.json".source = layoutPatched;
          # NOTE: `source = ./dir` makes home-manager create a SYMLINK at
          # ~/.config/herdr-app/mods/oz-pet pointing back into this repo. Every
          # later activation then writes *through* that link, replacing the
          # tracked files here with /nix/store symlinks and backing the old ones
          # up as .bak/.bak.bak — exactly how this directory got corrupted once
          # (commit 80688fe committed the symlinks). If it recurs, the .bak chain
          # still holds the original content.
          "herdr-app/mods/oz-pet" = {
            source = ./herdr-oz-pet;
            recursive = true;
            force = true;
          };
          "herdr-app/mods/oz-tabs" = {
            source = ./herdr-files/mods/oz-tabs;
            recursive = true;
            force = true;
          };
          "herdr-app/mods/oz-chrome" = {
            source = ./herdr-files/mods/oz-chrome;
            recursive = true;
            force = true;
          };
          "herdr-app/mods/automations" = {
            source = ./herdr-files/mods/automations;
            recursive = true;
            force = true;
          };
          "herdr-app/mods/atuin-threads" = {
            source = ./herdr-files/mods/atuin-threads;
            recursive = true;
            force = true;
          };
          "herdr-app/mods/insights" = {
            source = herdrInsights;
            recursive = true;
            force = true;
          };
          # github.com/AlonsoSG0/herdr-opencode-usage, copied into ./herdr-files
          # for the same reason as automations/atuin-threads.
          "herdr-app/mods/herdr-opencode-usage" = {
            source = ./herdr-files/mods/herdr-opencode-usage;
            recursive = true;
            force = true;
          };
          "herdr-app/themes/0oz.json".source = "${oz-design}/themes/0oz.json";
        }
        // builtins.listToAttrs (
          map
            (mod: {
              name = "herdr-app/mods/${mod}";
              value = {
                source = "${oz-design}/mods/${mod}";
                recursive = true;
                force = true;
              };
            })
            [
              "oz-changes"
              "oz-files"
              "oz-pane"
              "oz-spaces"
              "oz-status"
            ]
        );

        # Replace only Home Manager-created icon symlinks, after each activation.
        home.activation.herdrSvgAssets = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          for mod in oz-tabs oz-chrome automations atuin-threads insights herdr-opencode-usage oz-changes oz-files oz-pane oz-spaces oz-status; do
            dir="$HOME/.config/herdr-app/mods/$mod"
            [ -d "$dir" ] || continue
            while IFS= read -r -d $'\0' icon; do
              target="$(readlink -f -- "$icon")"
              case "$target" in
                /nix/store/*) run cp --remove-destination -- "$target" "$icon" ;;
              esac
            done < <(find "$dir" -type l -name '*.svg' -print0)
          done
        '';
      };
  };
}
