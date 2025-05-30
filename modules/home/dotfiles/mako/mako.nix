{ ... }:
{
  services.mako = {
    enable = true;
    sort = "-time";
    layer = "overlay";
    backgroundColor = "#2e3440";
    width = 300;
    height = 110;
    borderSize = 2;
    borderColor = "#88c0d0";
    borderRadius = 15;
    icons = false;
    maxIconSize = 64;
    defaultTimeout = 5000;
    ignoreTimeout = true;
    font = "monospace 14";

    # extraConfig = ''
    #   [urgency=low]
    #   border-color=#cccccc

    #   [urgency=normal]
    #   border-color=#d08770

    #   [urgency=high]
    #   border-color=#bf616a
    #   default-timeout=0

    #   [category=mpd]
    #   default-timeout=2000
    #   group-by=category
    # '';
  };
}
