{
  description = "Gridwatch APC UPS manager";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    bun2nix.url = "github:nix-community/bun2nix";
  };
  outputs = { self, nixpkgs, bun2nix }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      pkgsFor = system: import nixpkgs { inherit system; overlays = [ bun2nix.overlays.default ]; };
      perSystem = f: builtins.listToAttrs (map (system: { name = system; value = f system (pkgsFor system); }) systems);
    in {
      packages = perSystem (system: pkgs: { default = pkgs.callPackage ./nix/package.nix { }; });
      devShells = perSystem (system: pkgs: { default = pkgs.mkShell {
        packages = with pkgs; [ bun rustc cargo rustfmt clippy pkg-config vulkan-tools apcupsd ];
        buildInputs = with pkgs; [ vulkan-loader libxkbcommon wayland xkeyboard_config xorg.libX11 xorg.libxcb xorg.libXcursor xorg.libXi xorg.libXrandr fontconfig ];
        XKB_CONFIG_ROOT = "${pkgs.xkeyboard_config}/share/X11/xkb";
      }; });
      nixosModules.default = { pkgs, ... }@args: import ./nix/module.nix (args // { defaultPackage = self.packages.${pkgs.system}.default; });
      homeManagerModules.default = import ./nix/home-manager.nix;
    };
}
