{config, lib, pkgs,...}:
{
    programs.kitty = lib.mkForce {
        enable = true;
        shellIntegration.enableFishIntegration = true;
    };
}