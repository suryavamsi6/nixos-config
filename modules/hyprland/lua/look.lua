hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

hl.config({
  cursor = {
    no_hardware_cursors = true,
  },

  general = {
    gaps_in = 5,
    gaps_out = 20,
    border_size = 2,
    col = {
      active_border = {
        colors = { "rgba(33ccffee)", "rgba(00ff99ee)" },
        angle = 45,
      },
      inactive_border = "rgba(595959aa)",
    },
    resize_on_border = false,
    allow_tearing = false,
    layout = "master",
  },

  decoration = {
    rounding = 16,
    active_opacity = 0.95,
    inactive_opacity = 0.9,
    fullscreen_opacity = 0.95,
    dim_inactive = false,
    dim_strength = 0.05,
    blur = {
      enabled = true,
      size = 5,
      passes = 4,
      new_optimizations = true,
      xray = true,
      ignore_opacity = true,
    },
    shadow = {
      enabled = true,
      range = 50,
      render_power = 4,
      color = 0x99161925,
      color_inactive = 0x55161925,
    },
  },

  master = {
    new_status = "master",
    orientation = "center",
    mfact = 0.34,
  },

  misc = {
    force_default_wallpaper = -1,
    disable_hyprland_logo = false,
  },

  xwayland = {
    force_zero_scaling = true,
  },
})
