# Zen Browser + Sine, following upstream's manual installation
#
# https://github.com/sineorg/docs/blob/main/src/installation.md defines the
# steps, and this module performs them on Nix:
#
#   2. Extract the bootloader's program.zip into the browser's installation
#      directory (config.js + defaults/pref/config-prefs.js).
#   3. Extract the bootloader's profile.zip and Sine's engine.zip into the
#      active profile's chrome/ directory.
#   4/5. Clear the startup cache, then restart Zen.
#
# Step 2 targets the application directory, which is immutable store content
# on Nix, so it happens at build time on the *unwrapped* Zen derivation -- the
# one that owns lib/zen-bin-<version>/ -- and the flake's own wrapper is built
# on top of the result. Step 3 is a runtime action against whichever profile
# Zen is actually using, so nothing here takes ownership of profiles.ini or of
# any preference file.
{ lib, ... }:
{
  options.flake.modules.homeManager.zenBrowser = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      {
        pkgs,
        inputs,
        config,
        lib,
        ...
      }:
      let
        system = pkgs.stdenv.hostPlatform.system;

        # Bootloader v0.1.4 (states support for Sine v2.3+) and engine v2.3.3,
        # pinned by hash so a switch never depends on the network. program.zip
        # holds config.js + defaults/pref/config-prefs.js, profile.zip holds
        # utils/ (the chrome.manifest config.js registers), and engine.zip
        # holds JS/ (what that manifest maps chrome://userscripts to).
        bootloaderProgram = pkgs.fetchurl {
          url = "https://github.com/sineorg/bootloader/releases/download/v0.1.4/program.zip";
          hash = "sha256-VcwU69FBoy10bP6T/IrZhW6w1VPMNyfT5AhhfnPUrE0=";
        };
        bootloaderProfile = pkgs.fetchurl {
          url = "https://github.com/sineorg/bootloader/releases/download/v0.1.4/profile.zip";
          hash = "sha256-KFs9WJzJefEfAcnHdBC3F2lMzE8yzBywi9bYkJ+5jgA=";
        };
        sineEngine = pkgs.fetchurl {
          url = "https://github.com/CosmoCreeper/Sine/releases/download/v2.3.3/engine.zip";
          hash = "sha256-yYvo4CNOjE1bQdwne9IBo2Wi3MQY3LqC1HSdJ6ZKPWU=";
        };

        unwrapped = inputs.zen-browser.packages.${system}.twilight-unwrapped;

        # `defaults` is read-only in the store, and unzip needs to write next
        # to it, so restore write permission before extracting.
        zenWithAutoconfig = (import "${inputs.zen-browser}/wrap-zen.nix" pkgs.wrapFirefox) (
          unwrapped.overrideAttrs (old: {
            postInstall =
              (old.postInstall or "")
              + ''
                for libdir in "$out"/lib/zen-bin-*; do
                  chmod -R u+w "$libdir/defaults"
                  ${pkgs.unzip}/bin/unzip -oq ${bootloaderProgram} -d "$libdir"
                done
              '';
          })
        ) { };
      in
      {
        home.packages = [ zenWithAutoconfig ];

        # Upstream step 3. The profile is read out of Zen's own profiles.ini
        # rather than pinned here, so this keeps working when Zen creates or
        # selects a different profile, and the switch never rewrites that file.
        # The extraction is a copy, so Sine's engine auto-update keeps working
        # and simply gets reset to the pinned release on the next switch.
        home.activation.sineProfile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          set -eu
          zen_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/zen"
          ini="$zen_dir/profiles.ini"

          if [ ! -f "$ini" ]; then
            echo "sine: $ini does not exist yet; start Zen once and switch again" >&2
          else
            rel="$(${pkgs.gawk}/bin/awk -F= '
              /^\[Profile/ { n++; sect = 1; next }
              /^\[/        { sect = 0; next }
              sect && $1 == "Path" { path[n] = $2 }
              sect && $1 == "Default" && $2 == 1 { def = n }
              END {
                if (def != "" && (def in path)) print path[def]
                else if (1 in path) print path[1]
              }
            ' "$ini")"

            case "$rel" in
              /*) profile="$rel" ;;
              *) profile="$zen_dir/$rel" ;;
            esac

            if [ -z "$rel" ] || [ ! -d "$profile" ]; then
              echo "sine: no usable profile in $ini (Path=''${rel:-unset}'); skipping" >&2
            else
              chrome="$profile/chrome"
              mkdir -p "$chrome"
              ${pkgs.unzip}/bin/unzip -oq ${bootloaderProfile} -d "$chrome"
              ${pkgs.unzip}/bin/unzip -oq ${sineEngine} -d "$chrome"
              echo "sine: bootloader profile + engine extracted into $chrome"
              echo "sine: clear the startup cache in about:support, then restart Zen" >&2
            fi
          fi
        '';
      };
  };
}