{ config, pkgs, ... }:

let
  wallpaper = "../../wallpapers/leaf.png";
  fullpfp = "${config.home.homeDirectory}/Pictures/fullpfp.png";
in
{
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        immediate_render = true;
      };

      background = {
        monitor = "";
        path = wallpaper;
        color = "rgba(25, 20, 20, 1.0)";
        blur_passes = 0;
        blur_size = 2;
        noise = 0;
        contrast = 0;
        brightness = 0;
        vibrancy = 0;
        vibrancy_darkness = 0.0;
      };

      input-field = {
        monitor = "";
        size = "300, 30";
        outline_thickness = 0;
        dots_size = 0.25;
        dots_spacing = 0.55;
        dots_center = true;
        dots_rounding = -1;
        outer_color = "rgba(242, 243, 244, 0)";
        inner_color = "rgba(242, 243, 244, 0)";
        font_color = "rgba(242, 243, 244, 0.75)";
        fade_on_empty = false;
        placeholder_text = "";
        hide_input = false;
        check_color = "rgba(204, 136, 34, 0)";
        fail_color = "rgba(204, 34, 34, 0)";
        fail_text = "$FAIL <b>($ATTEMPTS)</b>";
        fail_transition = 300;
        capslock_color = -1;
        numlock_color = -1;
        bothlock_color = -1;
        invert_numlock = false;
        swap_font_color = false;
        position = "0, -468";
        halign = "center";
        valign = "center";
      };

      label = [
        {
          monitor = "";
          text = "cmd[update:1000] echo \"$(~/.config/scripts/song-status)\"";
          color = "rgba(242, 243, 244, 0.75)";
          font_size = 14;
          font_family = "SF Pro Text";
          position = "20, 512";
          halign = "left";
          valign = "center";
        }
        {
          monitor = "";
          text = "cmd[update:1000] echo \"$(~/.config/scripts/network-status)\"";
          color = "rgba(242, 243, 244, 0.75)";
          font_size = 16;
          font_family = "SF Pro Text";
          position = "-35, 512";
          halign = "right";
          valign = "center";
        }
        {
          monitor = "";
          text = "cmd[update:1000] echo \"$(~/.config/scripts/battery-status)\"";
          color = "rgba(242, 243, 244, 0.75)";
          font_size = 19;
          font_family = "SF Pro Text";
          position = "-93, 512";
          halign = "right";
          valign = "center";
        }
        {
          monitor = "";
          text = "cmd[update:1000] echo \"$(~/.config/scripts/layout-status)\"";
          color = "rgba(242, 243, 244, 0.75)";
          font_size = 15;
          font_family = "SF Pro Text";
          position = "-150, 512";
          halign = "right";
          valign = "center";
        }
        {
          monitor = "";
          text = "cmd[update:1000] echo \"$(date +\"%A, %B %d\")\"";
          color = "rgba(242, 243, 244, 0.75)";
          font_size = 20;
          font_family = "SF Pro Display Bold";
          position = "0, 405";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = "cmd[update:1000] echo \"$(date +\"%k:%M\")\"";
          color = "rgba(242, 243, 244, 0.75)";
          font_size = 93;
          font_family = "SF Pro Display Bold";
          position = "0, 310";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = "Surya";
          color = "rgba(242, 243, 244, 0.75)";
          font_size = 12;
          font_family = "SF Pro Display Bold";
          position = "0, -407";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = "Enter Password";
          color = "rgba(242, 243, 244, 0.75)";
          font_size = 10;
          font_family = "SF Pro Display";
          position = "0, -438";
          halign = "center";
          valign = "center";
        }
      ];

      image = {
        monitor = "";
        path = fullpfp;
        border_color = "0xffdddddd";
        border_size = 0;
        size = 73;
        rounding = -1;
        rotate = 0;
        reload_time = -1;
        reload_cmd = "";
        position = "0, -353";
        halign = "center";
        valign = "center";
      };
    };
  };
}
