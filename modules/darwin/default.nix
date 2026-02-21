# Auto-imports all darwin modules
{ ... }:
{
  imports = [
    ./defaults.nix
    ./security.nix
    ./homebrew.nix
  ];
}
