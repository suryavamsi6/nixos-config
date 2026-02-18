# MacBook M4 Air - nix-darwin system configuration
{
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ./../../modules/darwin/default.nix
  ];

  # Required for user-specific options (dock, finder, trackpad, homebrew)
  system.primaryUser = "suryavamsi";

  # Nix settings
  nix = {
    package = pkgs.nix;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };
    optimise.automatic = true;
    gc = {
      automatic = true;
      interval = {
        Weekday = 0;
        Hour = 2;
        Minute = 0;
      };
      options = "--delete-older-than 7d";
    };
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Set hostname
  networking.hostName = "macbook-air";

  # Timezone
  time.timeZone = "Asia/Calcutta";

  # System-level packages (minimal)
  environment.systemPackages = with pkgs; [
    vim
  ];

  # Fonts
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
  ];

  # Shell - enable fish system-wide
  environment.shells = [ pkgs.fish ];
  programs.fish.enable = true;
  environment.systemPath = [ "/run/current-system/sw/bin" ];

  # Homebrew integration for GUI apps
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
    };
    casks = [
      # Add macOS GUI apps here, e.g.:
      # "rectangle"
      # "alt-tab"
      # "firefox"
    ];
  };

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Used for backwards compatibility, don't change.
  system.stateVersion = 6;
}
