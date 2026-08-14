# Work tools (home-manager)
{ lib, ... }:
{
  options.flake.modules.homeManager.work = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      let
        # Linux CWA defaults RememberUsername=false (Windows defaults to true).
        # AuthManager then refuses to prefill the gateway login form.
        citrix = pkgs.citrix-workspace.overrideAttrs (old: {
          postFixup = (old.postFixup or "") + ''
            xml="$out/opt/citrix-icaclient/config/AuthManConfig.xml"
            if [ -f "$xml" ] && ! grep -q '<key>RememberUsername</key>' "$xml"; then
              chmod u+w "$xml"
              sed -i '/<\/dict>/i\
	<key>RememberUsername</key>\
	<value>true</value>' "$xml"
            fi
          '';
        });
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
