{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
    };
    helium-browser = {
      url = "github:oxcl/nix-flake-helium-browser";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    quickshell = {
      # add ?ref=<tag> to track a tag
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";

      # THIS IS IMPORTANT
      # Mismatched system dependencies will lead to crashes and other issues.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland.url = "github:hyprwm/Hyprland";
    hyprexpose = {
      url = "github:ThiagoAVicente/hyprexpose";
      flake = false;
    };
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    serpantinum = {
      url = "github:ilyamiro/serpantinum";
      flake = false;
    };
    shell-wallpapers = {
      url = "github:ilyamiro/shell-wallpapers";
      flake = false;
    };
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    gcb200-linux = {
      url = "github:suryavamsi6/gcb200-linux";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Official ChatGPT/Codex Linux desktop (Electron). Own nixpkgs on
    # purpose — it wraps the upstream .deb, not our tree.
    codex-desktop-linux.url = "github:ilysenko/codex-desktop-linux";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      imports = [ ./modules ];
    };
}
