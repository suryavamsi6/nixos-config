{ config, lib, pkgs, ... }:
let cfg = config.programs.gridwatch; in {
  options.programs.gridwatch = { enable = lib.mkEnableOption "Gridwatch desktop app"; package = lib.mkOption { type = lib.types.nullOr lib.types.package; default = null; }; };
  config = lib.mkIf (cfg.enable && cfg.package != null) {
    home.packages = [ cfg.package ];
  };
}
