{ config, pkgs, lib, ... }:
{
    nixpkgs.overlays = [
           (final: prev: {
            mcontrolcenter = prev.mcontrolcenter.overrideAttrs (
              old:  {
               src = prev.fetchFromGithub {
                   url = "https://github.com/dmitry-s93/MControlCenter/releases/download/0.5.0/MControlCenter-0.5.0-bin.tar.gz";
                   sha256 = "b5507918e229b15d06f1829f5d9fcc062a1c9d430468170ef4d31fdc4e8a8907";
               };
            });
            })
    ];


}