-- macOS-like motion: soft springs, subtle overshoot, floaty fades.
-- Speeds are in ds (1ds = 100ms). Keep angle animations non-looping on high-Hz OLED.

hl.config({
  animations = {
    enabled = true,
  },
})

-- Beziers (Apple-ish ease curves)
hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeOutExpo", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("easeOutCubic", { type = "bezier", points = { { 0.33, 1 }, { 0.68, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1 } } })

-- Springs tuned like macOS (mass≈1, moderate stiffness, gentle dampening = soft settle)
hl.curve("macosIn", { type = "spring", mass = 1, stiffness = 140, dampening = 18 })
hl.curve("macosOut", { type = "spring", mass = 1, stiffness = 180, dampening = 22 })
hl.curve("macosMove", { type = "spring", mass = 1, stiffness = 160, dampening = 20 })
hl.curve("macosSoft", { type = "spring", mass = 1, stiffness = 100, dampening = 16 })
hl.curve("macosLayer", { type = "spring", mass = 1, stiffness = 200, dampening = 24 })

-- Windows — scale-in like macOS app/window open
hl.animation({ leaf = "windows", enabled = true, speed = 5.5, spring = "macosIn", style = "popin 80%" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 5.2, spring = "macosIn", style = "popin 80%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 4.4, spring = "macosOut", style = "popin 90%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 5.0, spring = "macosMove" })

-- Layers (ags / walker / notifications) — soft sheet-style pop
hl.animation({ leaf = "layers", enabled = true, speed = 4.8, spring = "macosLayer", style = "popin 92%" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4.6, spring = "macosLayer", style = "popin 92%" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 3.6, bezier = "easeOutCubic", style = "fade" })

-- Fades — smooth opacity like macOS
hl.animation({ leaf = "fade", enabled = true, speed = 4.0, bezier = "easeOutCubic" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 3.4, bezier = "easeOutCubic" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 3.0, bezier = "easeOutCubic" })
hl.animation({ leaf = "fadeSwitch", enabled = true, speed = 3.6, bezier = "easeOutCubic" })
hl.animation({ leaf = "fadeShadow", enabled = true, speed = 3.6, bezier = "easeOutCubic" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 3.2, bezier = "easeOutCubic" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 2.6, bezier = "easeOutCubic" })

-- Borders
hl.animation({ leaf = "border", enabled = true, speed = 6.0, bezier = "easeOutQuint" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 80, bezier = "linear", style = "once" })

-- Workspaces — Mission Control–ish soft slide + fade
hl.animation({
  leaf = "workspaces",
  enabled = true,
  speed = 5.8,
  spring = "macosSoft",
  style = "slidefade 12%",
})
hl.animation({
  leaf = "workspacesIn",
  enabled = true,
  speed = 5.5,
  spring = "macosSoft",
  style = "slidefade 12%",
})
hl.animation({
  leaf = "workspacesOut",
  enabled = true,
  speed = 5.0,
  bezier = "easeOutExpo",
  style = "slidefade 12%",
})
hl.animation({
  leaf = "specialWorkspace",
  enabled = true,
  speed = 5.2,
  spring = "macosSoft",
  style = "slidefade 14%",
})
