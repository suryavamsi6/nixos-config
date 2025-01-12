{config, lib, pkgs,...}:
{
    program.kitty = lib.mkForce {
        enable = true;
        shellIntegration.enableFishIntegration = true;
    };
}