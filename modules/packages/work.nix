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
      postFixup = (old.postFixup or "") + ''
        xml="$out/opt/citrix-icaclient/config/AuthManConfig.xml"
        if [ -f "$xml" ] && ! grep -q '<key>RememberUsername</key>' "$xml"; then
          chmod u+w "$xml"
          sed -i '/<\/dict>/i\
	<key>RememberUsername</key>\
	<value>true</value>' "$xml"
        fi

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
        if [ -x "$ica/icasessionmgr" ]; then
          wrapProgram "$ica/icasessionmgr" \
            --set ICAROOT "$ica" \
            --set-default GDK_BACKEND x11 \
            --set-default EGL_PLATFORM x11 \
            --set-default QT_QPA_PLATFORM xcb
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
      };
  };

  options.flake.modules.homeManager.work = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
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
