{
  ...
}:
{

  # home.file.".config/kitty/kitty.conf" = {
  #   force = true;
  #   text = ''
  #     shell fish
  #   '';
  # };

  programs.kitty = {
    enable = true;
    theme = "Neutron";
    shellIntegration.enableFishIntegration = true;
  };

}
