{config, pkgs, ...} :
{
  programs.bash = {
    enable = false;
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
  };

}