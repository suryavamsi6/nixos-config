{pkgs, inputs,  ...}:
let
    autostart = import ./autostart.nix { inherit pkgs; };
    keybind = import ./keybind.nix { inherit pkgs; };
in
{   
    wayland.windowManager.hyprland = {
        enable = true;
        package = inputs.hyprland.packages."${pkgs.system}".hyprland;
        settings = autostart // keybind //{

            "$mainMod" = "SUPER";
            
            monitor = [
                "DP-1, highres,auto, 1"
                "eDP-1, disable"
            ];
            "$terminal" = "kitty";
            "$fileManager" = "dolphin";
            "$menu" = "walker";
            "$browser" = "zen";

            env = [
                "XCURSOR_SIZE = 24"
                "HYPRCURSOR_SIZE = 24"
            ];

            general = {
                gaps_in = 5;
                gaps_out = 20;
                border_size = 2;

                "col.active_border" = "rgba(33ccffee) rgba(00ff99ee) 45deg";
                "col.inactive_border" = "rgba(595959aa)";

                resize_on_border = false;
                allow_tearing = false;
                layout = "dwindle";
            };  

            decoration = {
                rounding = 16;
                active_opacity = 0.95;
                inactive_opacity = 0.9;
                fullscreen_opacity = 0.95;

                dim_inactive = false;
                dim_strength = 0.05;

                blur = {
                    enabled = true;
                    size = 5;
                    passes = 4;
                    new_optimizations = true;
                    xray = true;
                    ignore_opacity = true;
                };
                
                shadow = {
                    enabled = true;
                    range = 50;
                    render_power = 4;
                    color = "0x99161925";
                    color_inactive = "0x55161925";
                    ignore_window = true;
        
                };
                # Your blur "amount" is blur_size * blur_passes, but high blur_size (over around 5-ish) will produce artifacts.
                # if you want heavy blur, you need to up the blur_passes.
                # the more passes, the more you can up the blur_size without noticing artifacts.
            
                # Blurring layerSurfaces
                # blurls = gtk-layer-shell
                # blurls = waybar
                # blurls = lockscreen
                blurls = [
                    "gtk-layer-shell"
                    "waybar"
                    "lockscreen"
                    "rofi"
                    "wofi"
                    "launcher"
                ];

            };

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

            dwindle = {
                pseudotile = true;
                preserve_split = true;
            };

            master = {
                new_status = "master";
            };

            misc = {
                force_default_wallpaper = -1;
                disable_hyprland_logo = false;
            };

            xwayland = {
                force_zero_scaling = true;
            };

            input = {
                kb_layout = "us";
                kb_variant = "";
                kb_model = "";
                kb_options = "";
                kb_rules = "";

                follow_mouse = 1;
                sensitivity = 0;

                touchpad = {
                    natural_scroll = false;
                };
            }; 
            
            gestures = {
                workspace_swipe = false;
            };  

            device = {
                name = "epic-mouse-v1";
                sensitivity = -0.5;
            };



            windowrulev2 = [
                "suppressevent maximize, class:.*"
                "nofocus,class:^$,title:^$,xwayland:1,floating:1,fullscreen:0,pinned:0"
            ];


            # HDR messes up citrix displays
            experimental = {
                # hdr = true;
                wide_color_gamut = true;
                xx_color_management_v4 = true;
            };

        };
        };
}

