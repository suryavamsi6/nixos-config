{ ... }:
{
  environment.variables = {
    NIXOS_OZONE_WL = "1";
  };
  environment.sessionVariables = {
    STEAM_EXTRA_COMPAT_TOOLS_PATHS = "/home/$USER/.steam/root/compatibilitytools.d";
  };
}
