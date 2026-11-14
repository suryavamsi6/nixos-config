# MonoCode Native (hardbeat920/monocode) -- the experimental Rust + GPUI
# desktop app from the native-v* prerelease tags; the Tauri/WebKit AppImage
# packaging (monocode-desktop.nix) is gone, replaced by this.
#
# Linux ships only .deb/.rpm/AppImage; this packages the pinned release
# .deb: pure data (usr/lib/monocode-native/monocode-gpui plus a desktop
# entry), unpacked with dpkg-deb and run in a buildFHSEnv, which provides
# the /lib64 interpreter the glibc build expects.
#
# GPUI renders through Vulkan and dlopens the X11/wayland stack at runtime,
# so the FHS env carries vulkan-loader and the windowing libraries instead
# of WebKitGTK; the NVIDIA ICD comes from /run/opengl-driver, which the FHS
# env mounts from the host. Updates stay with this pin (prerelease series;
# update-pins follows it via the native-v tag prefix). Bump monocodeVersion
# and the hash together, or run `nix run .#update-pins`.
{ lib, ... }:
{
  options.flake.modules.homeManager.monocode = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      let
        monocodeVersion = "0.16.0-preview.14";
        monocodeSrc = pkgs.fetchurl {
          url = "https://github.com/hardbeat920/monocode/releases/download/native-v${monocodeVersion}/monocode-native_${monocodeVersion}_amd64.deb";
          hash = "sha256-M6r8VTnFPxXgy7i3VtWo0+kmZP6s7c8XwcmqWkXMPNI=";
        };
        monocodeContents = pkgs.runCommand "monocode-native-deb" { } ''
          ${pkgs.dpkg}/bin/dpkg-deb -x ${monocodeSrc} $out
        '';
        monocodeRun = pkgs.writeShellScript "monocode-native-run" ''
          # GUI launches do not inherit the interactive shell's SSH agent
          # environment. Forward 1Password's agent socket so native agent
          # sessions can authenticate with the keys configured there.
          if [ -z "''${SSH_AUTH_SOCK:-}" ] && [ -S "$HOME/.1password/agent.sock" ]; then
            export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"
          fi
          # Prefer the sandbox-aware `op` shim over the plain store CLI.
          export PATH="${opShim}/bin:$PATH"
          exec ${monocodeContents}/usr/lib/monocode-native/monocode-gpui "$@"
        '';
        # NixOS ships `op` as a setgid(onepassword-cli) wrapper. Inside the
        # FHS buildFHSEnv sandbox the user namespace maps only the primary gid
        # and sets PR_SET_NO_NEW_PRIVS, so that setgid cannot take effect: the
        # CLI then connects as the ambient gid and the 1Password desktop app
        # rejects the peer with PipeAuthError(NoCreds) (visible in its log as
        # "invalid group attempted to connect, rejecting remote"). Re-exec the
        # command in the user manager's namespace, where the wrapper elevates
        # normally and stdin/stdout still pass through.
        opShim = pkgs.writeShellScriptBin "op" ''
          real=/run/wrappers/bin/op
          nnp=0
          if [ -r /proc/self/status ]; then
            while IFS=: read -r key value; do
              if [ "$key" = "NoNewPrivs" ]; then
                case "''${value//[[:space:]]/}" in
                  1) nnp=1 ;;
                esac
              fi
            done < /proc/self/status
          fi
          if [ "$nnp" = 1 ] && [ -x "$real" ]; then
            # Forward only the variables `op` and the user manager need;
            # compgen -e is unavailable in some bash builds, so read the
            # NUL-separated environ directly.
            envs=()
            while IFS= read -r -d "" entry; do
              case "''${entry%%=*}" in
                OP_* | XDG_* | SSH_AUTH_SOCK | HOME | PATH | DBUS_SESSION_BUS_ADDRESS)
                  envs+=("--setenv=$entry")
                  ;;
              esac
            done < /proc/self/environ
            exec ${pkgs.systemd}/bin/systemd-run --user --quiet --collect --pipe --wait \
              --unit="op-$$-''${RANDOM}" "''${envs[@]}" "$real" "$@"
          fi
          exec "''${real:-${pkgs._1password-cli}/bin/op}" "$@"
        '';
        monocodeNative = pkgs.buildFHSEnv (
          pkgs.appimageTools.defaultFhsEnvArgs
          // {
            pname = "monocode-native";
            version = monocodeVersion;

            # The GPUI binary links libdbus/libsystemd/libxcb/libxkbcommon;
            # vulkan and the X11/wayland extensions are dlopen'd at runtime.
            targetPkgs =
              p:
              pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs p
              ++ [
                p.vulkan-loader
                p.dbus
                p.systemd
                # Agent sessions are launched by MonoCode's native GUI,
                # not by a login shell. Keep the 1Password CLI on the FHS
                # environment's PATH so Pi/Codex MCP tools can resolve `op`;
                # opShim is prepended to PATH by the runScript below.
                p._1password-cli
                opShim
                p.libxkbcommon
                p.wayland
                p.libx11
                p.libxcb
                p.libxcursor
                p.libxi
                p.libxrandr
              ];

            # Run through the host-aware launcher so the GUI and its child
            # coding agents inherit the 1Password SSH agent socket.
            runScript = "${monocodeRun}";

            # 1Password's Linux CLI integration uses an abstract Unix socket,
            # which is scoped to the network namespace (not XDG_RUNTIME_DIR).
            # Share the host network namespace so `op` inside MonoCode reaches
            # the desktop app; also keep the user's runtime socket paths visible.
            extraBwrapArgs = [
              "--share-net"
              ''--bind-try "$XDG_RUNTIME_DIR" "$XDG_RUNTIME_DIR"''
            ];

            extraInstallCommands = ''
              install -Dm444 ${monocodeContents}/usr/share/applications/monocode-native.desktop \
                $out/share/applications/monocode-native.desktop
              install -Dm444 ${monocodeContents}/usr/share/icons/hicolor/256x256/apps/monocode-native.png \
                $out/share/icons/hicolor/256x256/apps/monocode-native.png
            '';

            meta = {
              description = "One UI for every coding-agent harness (native GPUI preview)";
              homepage = "https://github.com/hardbeat920/monocode";
              license = lib.licenses.mit;
              sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
              platforms = [ "x86_64-linux" ];
              mainProgram = "monocode-native";
            };
          }
        );
      in
      {
        # An upstream AppImage/deb run writes its own entry under
        # XDG_DATA_HOME, which is searched before the profile and would keep
        # a store Exec. force replaces that file instead of aborting
        # activation.
        xdg.dataFile."applications/monocode-native.desktop" = {
          source = "${monocodeNative}/share/applications/monocode-native.desktop";
          force = true;
        };

        home.packages = [ monocodeNative ];
      };
  };
}
