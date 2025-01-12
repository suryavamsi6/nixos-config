{config, pkgs, ...} :
{
  programs.bash = {
    enable = false;
  };

  program.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
  }

}