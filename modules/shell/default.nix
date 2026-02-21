# Shell — Fish + Kitty + bash-to-fish wrapper (NixOS + home-manager)
{ lib, ... }:
{
  # NixOS-level shell config
  options.flake.modules.nixos.shell = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, ... }: {
      programs.bash.interactiveShellInit = ''
        if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
        then
          shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
          exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
        fi
      '';
      environment.shells = [ pkgs.fish ];
      programs.fish.enable = true;
    };
  };

  # Darwin-level shell config
  options.flake.modules.darwin.shell = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, ... }: {
      environment.shells = [ pkgs.fish ];
      programs.fish.enable = true;
      environment.systemPath = [ "/run/current-system/sw/bin" ];
    };
  };

  # Home-manager-level shell config (Linux)
  options.flake.modules.homeManager.shell = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, ... }: {
      programs.fish = {
        enable = true;
        plugins = [
          {
            name = "tide";
            src = pkgs.fishPlugins.tide.src;
          }
          {
            name = "z";
            src = pkgs.fishPlugins.z.src;
          }
        ];
      };

      programs.kitty = {
        enable = true;
        themeFile = "Catppuccin-Mocha";
        shellIntegration.enableFishIntegration = true;
      };
    };
  };

  # Home-manager-level shell config (Darwin)
  options.flake.modules.homeManager.shellDarwin = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, lib, ... }: {
      programs.fish = {
        enable = true;
        interactiveShellInit = ''
          # Disable default greeting
          set -g fish_greeting
        '';
        shellAbbrs = {
          rebuild = "sudo darwin-rebuild switch --flake ~/Dotfiles/nixos-config#macbook-air";
        };
        shellInit = ''
          # Add nix-darwin and nix profile paths
          fish_add_path --move --path /run/current-system/sw/bin
          fish_add_path --move --path /nix/var/nix/profiles/default/bin
        '';
      };

      programs.starship = {
        enable = true;
        enableFishIntegration = true;
      };
    };
  };
}
