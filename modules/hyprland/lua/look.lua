local home = os.getenv("HOME") or "/home/surya"
local colors = {
  active_border = "rgba(89b4faee)",
  inactive_border = "rgba(45475aaa)",
}
local ok, loaded = pcall(dofile, home .. "/.config/hypr/colors.lua")
if ok and type(loaded) == "table" then
  if loaded.active_border then
    colors.active_border = loaded.active_border
  end
  if loaded.inactive_border then
    colors.inactive_border = loaded.inactive_border
  end
end

hl.env("XCURSOR_THEME", "ArcMidnight-Cursors")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "ArcMidnight-Cursors")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("TERMINAL", "kitty")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("NIXOS_OZONE_WL", "1")

hl.config({
  cursor = {
    no_hardware_cursors = true,
  },

  general = {
    gaps_in = 4,
    gaps_out = 4,
    border_size = 2,
    col = {
      active_border = { colors = { colors.active_border }, angle = 45 },
      inactive_border = colors.inactive_border,
    },
    resize_on_border = true,
    allow_tearing = false,
    layout = "dwindle",
  },

  decoration = {
    rounding = 4,
    active_opacity = 1.0,
    inactive_opacity = 1.0,
    dim_inactive = false,
    dim_strength = 0.19,
    dim_around = 0.6,
    shadow = {
      enabled = false,
    },
    blur = {
      enabled = true,
      size = 8,
      passes = 2,
      new_optimizations = true,
    },
  },

  dwindle = {
    preserve_split = true,
    smart_resizing = true,
  },

  master = {
    new_status = "master",
  },

  misc = {
    -- 2 = fullscreen only. Always-on VRR (1) flickers OLEDs on a static desktop.
    vrr = 2,
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    force_default_wallpaper = 0,
    focus_on_activate = true,
  },

  xwayland = {
    force_zero_scaling = true,
  },
})

hl.layer_rule({
  match = { namespace = "volume_osd" },
  no_anim = true,
})
hl.layer_rule({
  match = { namespace = "brightness_osd" },
  no_anim = true,
})
hl.layer_rule({
  match = { namespace = "hyprpicker" },
  no_anim = true,
})
hl.layer_rule({
  match = { namespace = "qsdock" },
  no_anim = true,
})
hl.layer_rule({
  match = { namespace = "ext-session-lock" },
  blur = true,
  ignore_alpha = 0.2,
})
