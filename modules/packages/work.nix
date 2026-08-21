# Work tools (Citrix + Zoom VDI plugin)
{ lib, ... }:
let
  zoomvdiFor = pkgs: pkgs.callPackage ./zoomvdi-universal-plugin.nix { };

  citrixFor =
    pkgs:
    let
      zoomvdi = zoomvdiFor pkgs;
    in
    pkgs.citrix-workspace.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
      postFixup = (old.postFixup or "") + ''
        xml="$out/opt/citrix-icaclient/config/AuthManConfig.xml"
        if [ -f "$xml" ]; then
          chmod u+w "$xml"
          if ! grep -q '<key>RememberUsername</key>' "$xml"; then
            sed -i '/<\/dict>/i\
	<key>RememberUsername</key>\
	<value>true</value>' "$xml"
          fi
        fi
        # Entra/SAML deliberately stays on the embedded WebKitGTK dialog.
        # Turning on AADSSOWithFido2AuthenticationEnabled / SharedAuthContext /
        # FIDO2Enabled hands login to FIDO2AuthBrowser instead, and Citrix only
        # launches known browser names — so it opens a bare Firefox with no MS
        # session or passkeys rather than showing a popup, and the attempt ends
        # as LogonResult_CancelledByUser. Keep the vendor defaults (false).

        ica="$out/opt/citrix-icaclient"
        ln -sf ${zoomvdi.pluginLib} "$ica/ZoomMedia.so"
        for f in "$ica/config/module.ini" "$ica/nls/"*/module.ini; do
          [ -f "$f" ] || continue
          grep -q 'DriverName=ZoomMedia.so' "$f" && continue
          chmod u+w "$f"
          sed -i \
            -e 's/^VirtualDriver = .*/&, ZoomMedia/' \
            -e '/^VDSCAN *= *On/a ZoomMedia=On' \
            "$f"
          printf '\n[ZoomMedia]\nDriverName=ZoomMedia.so\n' >> "$f"
        done

        # icasessionmgr execs $ICAROOT/wfica, not PATH. Keep it on this tree.
        # Firefox stays on PATH only so links opened from the store UI resolve;
        # login itself does not use it (see the AuthManConfig note above).
        # The WEBKIT_* flags matter for the embedded login dialog on NVIDIA.
        # wrapGAppsHook replaces wrapProgram with makeCWrapper, which rejects
        # --run. wrapProgramShell is the bash wrapper that still supports it.
        if [ -x "$ica/icasessionmgr" ]; then
          wrapProgramShell "$ica/icasessionmgr" \
            --set ICAROOT "$ica" \
            --prefix PATH : "${lib.makeBinPath [ pkgs.firefox ]}" \
            --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ pkgs.libpulseaudio ]}" \
            --set PULSE_LATENCY_MSEC 30 \
            --run "ulimit -c unlimited" \
            --set-default GDK_BACKEND x11 \
            --set-default EGL_PLATFORM x11 \
            --set-default QT_QPA_PLATFORM xcb \
            --set WEBKIT_DISABLE_COMPOSITING_MODE 1 \
            --set WEBKIT_DISABLE_DMABUF_RENDERER 1
        fi
      '';
    });
in
{
  options.flake.modules.nixos.work = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      let
        zoomvdi = zoomvdiFor pkgs;
        citrix = citrixFor pkgs;
      in
      {
        environment.etc."zoomvdi/ZoomMedia.ini".source = "${zoomvdi}/etc/zoomvdi/ZoomMedia.ini";
        environment.etc."zoomvdi/citrix/ZoomMedia.ini".source = "${zoomvdi}/etc/zoomvdi/citrix/ZoomMedia.ini";
        # Plugin probes `/opt/Citrix/ICAClient/wfica -version` (hardcoded).
        systemd.tmpfiles.rules = [
          "L+ /opt/Citrix/ICAClient - - - - ${citrix}/opt/citrix-icaclient"
          "L+ /usr/lib/zoomvdi-universal-plugin - - - - ${zoomvdi}/lib/zoomvdi-universal-plugin"
        ];

        # Citrix CLStore talks to Secret Service. Do not enable GCR's SSH
        # agent — 1Password owns SSH_AUTH_SOCK.
        services.gnome.gnome-keyring.enable = true;
        services.gnome.gcr-ssh-agent.enable = false;
        security.pam.services.greetd.enableGnomeKeyring = true;

        # Auth daemons outlive `nh os switch` and pin `-icaroot` to the old
        # store path. A leftover ServiceRecord makes nFactor login cancel in
        # ~3s with no dialog. Reap only those whose binary/icaroot is not
        # this generation — never wfica / icasessionmgr (live session).
        systemd.services.citrix-reap-stale = {
          description = "Kill Citrix auth daemons left on a previous store path";
          wantedBy = [ "multi-user.target" ];
          after = [ "systemd-tmpfiles-resetup.service" ];
          restartIfChanged = true;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            current=${citrix}
            for proc in /proc/[0-9]*; do
              pid=''${proc#/proc/}
              comm=$(cat "$proc/comm" 2>/dev/null) || continue
              case "$comm" in
                *ServiceRecord*|*AuthManager*|*selfservice*|*ctxwebhelper*|*storebrowse*) ;;
                *) continue ;;
              esac
              exe=$(readlink "$proc/exe" 2>/dev/null) || continue
              cmdline=$(tr '\0' ' ' < "$proc/cmdline" 2>/dev/null) || continue
              case "$exe $cmdline" in
                *citrix-workspace*) ;;
                *) continue ;;
              esac
              case "$exe $cmdline" in
                *$current*) continue ;;
              esac
              echo "citrix-reap-stale: pid $pid ($comm) is on a previous generation"
              kill "$pid" 2>/dev/null || true
            done
          '';
        };
      };
  };

  options.flake.modules.homeManager.work = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, lib, ... }:
      let
        citrix = citrixFor pkgs;
        # WebKitGTK login (selfservice) segfaults when GDK prefers Wayland on NVIDIA.
        citrixX11 = pkgs.symlinkJoin {
          name = "citrix-workspace-x11";
          paths = [ citrix ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapBin() {
              local name="$1"
              if [ -e "${citrix}/bin/$name" ]; then
                rm -f "$out/bin/$name"
                makeWrapper "${citrix}/bin/$name" "$out/bin/$name" \
                  --prefix PATH : "${lib.makeBinPath [ pkgs.firefox ]}" \
                  --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ pkgs.libpulseaudio ]}" \
                  --set PULSE_LATENCY_MSEC 30 \
                  --set GDK_BACKEND x11 \
                  --set QT_QPA_PLATFORM xcb \
                  --unset QT_QPA_PLATFORMTHEME \
                  --set WEBKIT_DISABLE_COMPOSITING_MODE 1 \
                  --set WEBKIT_DISABLE_DMABUF_RENDERER 1
              fi
            }
            wrapBin selfservice
            wrapBin wfica
            wrapBin adapter
            wrapBin storebrowse
            wrapBin ctxwebhelper
            wrapBin configmgr
            wrapBin conncenter

            rm -rf "$out/share/applications"
            cp -a "${citrix}/share/applications" "$out/share/applications"
            chmod -R u+w "$out/share/applications"
            find "$out/share/applications" -name '*.desktop' -exec \
              sed -i "s|${citrix}/bin/|$out/bin/|g" {} +
          '';
        };
      in
      {
        home.packages = [
          pkgs.ntfs3g
          pkgs.zoom-us
          citrixX11
        ];
      };
  };
}
