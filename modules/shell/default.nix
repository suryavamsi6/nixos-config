# Shell — Fish + Ghostty + bash-to-fish wrapper (NixOS + home-manager)
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
    default = { pkgs, config, ... }:
      let
        matugenGhostty = pkgs.writeShellApplication {
          name = "serpantinum-matugen-ghostty";
          runtimeInputs = [ pkgs.python3 ];
          text = ''
            exec ${pkgs.python3}/bin/python3 ${./matugen-ghostty.py} \
              "${config.xdg.stateHome}/serpantinum/qs_matugen_colors.json" \
              "${config.xdg.configHome}/ghostty/matugen.conf" \
              "${config.xdg.configHome}/starship.toml" \
              "${config.xdg.configHome}/starship-matugen.toml"
          '';
        };
      in {
        home.sessionVariables.STARSHIP_CONFIG = lib.mkForce "${config.xdg.configHome}/starship-matugen.toml";
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

        # Expose 1Password SSH agent socket so git push uses the GitHub key.
        shellInit = ''
          if test -S "$HOME/.1password/agent.sock"
            set -gx SSH_AUTH_SOCK "$HOME/.1password/agent.sock"
          end
        '';
      };

      programs.ghostty = {
        enable = true;
        enableFishIntegration = true;
        settings = {
          # The generated file is refreshed whenever Serpantinum regenerates Matugen colors.
          "config-file" = "${config.xdg.configHome}/ghostty/matugen.conf";
          font-family = "JetBrains Mono";
          font-size = 13;
          background-opacity = 1.0;
          confirm-close-surface = false;
          scrollback-limit = 2000;
          shell-integration-features = "no-cursor";
        };
      };
      systemd.user.services.serpantinum-matugen-ghostty = {
        Unit = {
          Description = "Generate Ghostty colors from Serpantinum Matugen output";
          After = [ "graphical-session.target" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${matugenGhostty}/bin/serpantinum-matugen-ghostty";
        };
      };
      systemd.user.paths.serpantinum-matugen-ghostty = {
        Path = {
          PathChanged = "${config.xdg.stateHome}/serpantinum/qs_matugen_colors.json";
          Unit = "serpantinum-matugen-ghostty.service";
        };
        Install.WantedBy = [ "default.target" ];
      };

      programs.starship = {
        enable = true;
        enableFishIntegration = true;
        settings = lib.mkMerge [
          (builtins.fromTOML (
            builtins.readFile "${pkgs.starship}/share/starship/presets/catppuccin-powerline.toml"
          ))
          {
            # here goes my custom configurations
            palette = lib.mkForce "catppuccin_macchiato";
          }
        ];
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
          # Hermes setup appends this itself, then aborts when this file is a Nix store symlink.
          fish_add_path --move --path "$HOME/.local/bin"
        '';
      };

      programs.starship = {
        enable = true;
        enableFishIntegration = true;
      };
    };
  };
}
