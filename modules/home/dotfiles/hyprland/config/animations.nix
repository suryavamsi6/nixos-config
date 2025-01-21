{ pkgs, ... }:
{
  animations = {
    enabled = true;
    bezier = [
      "easeOutQuint,0.23,1,0.32,1"
      "easeInOutCubic,0.65,0.05,0.36,1"
      "linear,0,0,1,1"
      "almostLinear,0.5,0.5,0.75,1.0"
      "quick,0.15,0,0.1,1"
      "overshot,0.13,0.99,0.29,1.1"
      "shot,0.2,1.0,0.2,1.0"
      "swipe,0.6,0.0,0.2,1.05"
      "linear,0.0,0.0,1.0,1.0"
      "progressive,1.0,0.0,0.6,1.0"
    ];
    animation = [
      "windows,1,6,shot,slide"
      "workspaces,1,6,overshot,slidevert"
      "fade,1,4,linear"
      "border,1,4,linear"
      "borderangle,1,180,linear"
    ];
  };
}
