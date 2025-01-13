{config, lib, pkgs,...}:
{
    programs.starship = {
        enable = true;
        enableFishIntegration = true;
    };

     home.file.".config/kitty/kitty.conf" = {
        force = true;
        text = ''
        shell fish
        '';
     };

}