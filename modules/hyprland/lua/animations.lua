-- Snappy, layered motion: springs for windows, soft fades, workspace slidefade.
-- Speeds are in ds (1ds = 100ms). Keep angle animations non-looping on high-Hz OLED.

hl.config({
  animations = {
    enabled = true,
  },
})

-- Beziers
hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeOutExpo", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })

-- Springs (mass≈1; higher stiffness = snappier, higher dampening = less bounce)
hl.curve("winIn", { type = "spring", mass = 1, stiffness = 250, dampening = 28 })
hl.curve("winOut", { type = "spring", mass = 1, stiffness = 320, dampening = 36 })
hl.curve("winMove", { type = "spring", mass = 1, stiffness = 280, dampening = 30 })
hl.curve("soft", { type = "spring", mass = 1, stiffness = 180, dampening = 24 })

-- Windows
hl.animation({ leaf = "windows", enabled = true, speed = 4.5, spring = "winIn", style = "popin 88%" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.2, spring = "winIn", style = "popin 88%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3.2, spring = "winOut", style = "popin 92%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4.0, spring = "winMove" })

-- Layers (ags / walker / notifications)
hl.animation({ leaf = "layers", enabled = true, speed = 3.6, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 3.8, bezier = "easeOutExpo", style = "popin 95%" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 2.4, bezier = "quick", style = "fade" })

-- Fades
hl.animation({ leaf = "fade", enabled = true, speed = 3.0, bezier = "quick" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 2.2, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.8, bezier = "almostLinear" })
hl.animation({ leaf = "fadeSwitch", enabled = true, speed = 2.5, bezier = "quick" })
hl.animation({ leaf = "fadeShadow", enabled = true, speed = 2.5, bezier = "quick" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 2.0, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.6, bezier = "almostLinear" })

-- Borders (gradient angle once — never loop at 175Hz)
hl.animation({ leaf = "border", enabled = true, speed = 5.0, bezier = "easeOutQuint" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 80, bezier = "linear", style = "once" })

-- Workspaces / scratchpad
hl.animation({
  leaf = "workspaces",
  enabled = true,
  speed = 4.5,
  bezier = "easeOutExpo",
  style = "slidefadevert 18%",
})
hl.animation({
  leaf = "workspacesIn",
  enabled = true,
  speed = 4.2,
  bezier = "easeOutExpo",
  style = "slidefadevert 18%",
})
hl.animation({
  leaf = "workspacesOut",
  enabled = true,
  speed = 3.8,
  bezier = "easeOutQuint",
  style = "slidefadevert 18%",
})
hl.animation({
  leaf = "specialWorkspace",
  enabled = true,
  speed = 4.0,
  spring = "soft",
  style = "slidefade 16%",
})
