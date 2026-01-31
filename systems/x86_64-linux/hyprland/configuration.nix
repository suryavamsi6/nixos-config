# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  config,
  pkgs,
  ...
}:
{

  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./../../../modules/nixos/default.nix
    ./../../../packages/nixos/default.nix
  ];

  gnome.enable = false;
  hyprland.enable = true;

  nix = {
    package = pkgs.nix;
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    settings = {
      auto-optimise-store = true;
      substituters = [ "https://hyprland.cachix.org" ];
      trusted-public-keys = [ "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };

  services.samba = {
    enable = true;
    # package = pkgs.samba4Full; # Consider using samba4Full for more features if needed
     # Each user has to authenticate with a password

    # Optional: Define a workgroup if needed, default is WORKGROUP
    # extraConfig = ''
    #   workgroup = YOUR_WORKGROUP
    # '';

    settings = {
      global.security = "user";
      # This is a name for your share, e.g., "pibackups"
      # The Raspberry Pi will connect to this share name.
      "pibackups" = {
        path = "/home/surya/Backup_Pi"; # Path to the directory you want to share
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no"; # Disallow guest access, require authentication
        "valid users" = "surya"; # Specify which NixOS user(s) can access this share
        # You can list multiple users: "user1 user2"
        # Or use a group:
        # "valid users" = "@yourgroup";
        "create mask" = "0664"; # File permissions for new files
        "directory mask" = "0775"; # Directory permissions for new directories
      };

      # You can add more shares here if needed
      # "another_share" = {
      #   path = "/path/to/another/directory";
      #   # ... other options ...
      # };
    };

    # If you have a firewall enabled in NixOS (networking.firewall.enable = true;),
    # you might need to open the Samba ports.
    # The `services.samba.openFirewall = true;` option should handle this.
    openFirewall = true;
  };

  # If you want to make your NixOS machine discoverable by name (NetBIOS)
  # for easier access from some clients (like Windows, or your Pi if it has Avahi/WS-Discovery):
  services.samba-wsdd.enable = true; # For WS-Discovery (newer Windows, some Linux)
  # services.nmbd.enable = true; # For NetBIOS Name Service (older, but sometimes still useful; part of `services.samba` typically)

  # Bootloader.
  #   boot.loader.systemd-boot.enable = true;
  #   boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Set your time zone.
  time.timeZone = "Asia/Kolkata";
  nixpkgs.config.permittedInsecurePackages = [
    "libxml2-2.13.8"
    "libsoup-2.74.3"
  ];
  # Select internationalisation properties.
  i18n.defaultLocale = "en_IN";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_IN";
    LC_IDENTIFICATION = "en_IN";
    LC_MEASUREMENT = "en_IN";
    LC_MONETARY = "en_IN";
    LC_NAME = "en_IN";
    LC_NUMERIC = "en_IN";
    LC_PAPER = "en_IN";
    LC_TELEPHONE = "en_IN";
    LC_TIME = "en_IN";
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.surya = {
    isNormalUser = true;
    description = "Surya Vamsi";
    extraGroups = [
      "networkmanager"
      "wheel"
      "openrazer"
      "disk"
    ];
    packages = [
      #  thunderbird
    ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?

  services.xserver.videoDrivers = [ "nvidia" ];
  # environment.systemPackages = [ pkgs.lan-mouse_git ];
  #chaotic.mesa-git.enable = true;

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = false;
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.beta;
  };

  services.logind = {
    # This tells systemd-logind to ignore the lid switch when the laptop is on battery or external power.
    # "ignore" means it won't trigger suspend, hibernate, or lock.
    settings.Login.HandleLidSwitch = "ignore";
    settings.Login.HandleLidSwitchExternalPower = "ignore"; # For when on AC power
    settings.Login.HandleLidSwitchDocked = "ignore"; # For when docked (if applicable)

    # You might also want to ignore other power-related keys if you don't want them to trigger actions
    # HandlePowerKey = "ignore";
    # HandleSuspendKey = "ignore";
    # HandleHibernateKey = "ignore";
  };

  hardware.graphics = {
    package = pkgs.mesa;

    # if you also want 32-bit support (e.g for Steam)
    enable32Bit = true;
    package32 = pkgs.pkgsi686Linux.mesa;
  };

}
