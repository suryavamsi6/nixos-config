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
    opencode = {
      url = "github:anomalyco/opencode/v2.2.5";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hunk = {
      url = "github:modem-dev/hunk";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-flatpak = {
      url = "github:gmodena/nix-flatpak/?ref=v0.6.0";
    };
    hyprland.url = "github:hyprwm/Hyprland";
    hyprexpose = {
      url = "github:ThiagoAVicente/hyprexpose";
      flake = false;
    };
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    serpantinum.url = "github:ilyamiro/serpantinum/44d33831ab6314e7d2d7f0323c1fc023cb08804c";
    world-clock = {
      url = "path:./vendor/world-clock";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.serpantinum.follows = "serpantinum";
    };
    gridwatch = {
      url = "path:./vendor/gridwatch";
      inputs.nixpkgs.follows = "nixpkgs";
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
    # Clan: fleet inventory, machine evaluation, and `clan vars` secrets.
    # Pinned onto OUR nixpkgs rather than clan-core's (the template's
    # `nixpkgs.follows = "clan-core/nixpkgs"` would silently move our pin).
    clan-core = {
      url = "https://git.clan.lol/clan/clan-core/archive/main.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nix-darwin.follows = "nix-darwin";
      inputs.flake-parts.follows = "flake-parts";
    };
    # deploy-rs: `deploy .#host` = build, copy, activate, magic rollback.
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      imports = [ ./modules ];
      # `nix run .#update-pins` audits every pinned app, prefetches the new
      # hashes, and (with --write) rewrites the modules. See the script header.
      perSystem =
        { pkgs, system, ... }:
        {
          # Ad-hoc access to Clan's CLI on every system this flake evaluates,
          # darwin included — homeManager.dev (which installs it on the desktop)
          # is not imported by the Mac. `nix run .#clan-cli`.
          packages.clan-cli = inputs.clan-core.packages.${system}.clan-cli;
          packages.update-pins = pkgs.writeShellApplication {
            name = "update-pins";
            runtimeInputs = [
              pkgs.python3
              pkgs.nix
              pkgs.curl
              pkgs.git
              pkgs.cacert
            ];
            text = ''
              export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
              exec python3 ${./scripts/update-pins.py} "$@"
            '';
          };
        };
    };
}
