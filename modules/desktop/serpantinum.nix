# Official Serpantinum NixOS/Home Manager integration.
{ lib, ... }:
{
  options.flake.modules.nixos.serpantinum = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { inputs, ... }:
      {
        imports = [ (import "${inputs.serpantinum}/nix/nixos-module.nix") ];
        programs.serpantinum.enable = true;
      };
  };

  options.flake.modules.homeManager.serpantinum = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { inputs, pkgs, ... }:
      let
        serpantinum = pkgs.callPackage "${inputs.serpantinum}/nix/package.nix" { };
        serpantinumPatched = serpantinum.overrideAttrs (old: {
          postInstall = (old.postInstall or "") + ''
            substituteInPlace $out/share/serpantinum/quickshell/bar/modules/system/BtWidget.qml \
              --replace-fail 'moduleActive && !isDesktop && sysLayout.implicitWidth > 0' \
                             'moduleActive && sysLayout.implicitWidth > 0' \
              --replace-fail 'showLayout && moduleActive && !isDesktop' \
                             'showLayout && moduleActive' \
              --replace-fail 'isDesktop ? 0 : implicitWidth' 'implicitWidth'
          '';
        });
      in
      {
        imports = [
          (import "${inputs.serpantinum}/nix/hm-module.nix" {
            self = inputs.serpantinum;
          })
        ];
        programs.serpantinum.enable = true;
        programs.serpantinum.package = serpantinumPatched;
        programs.serpantinum.systemd.enable = true;
        programs.serpantinum.settings.launcher.terminalCommand = "ghostty -e";

      };
  };
}
