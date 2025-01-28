{ pkgs, ... }:
{

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

}
