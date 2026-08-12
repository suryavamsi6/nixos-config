hl.window_rule({
  name = "suppress-maximize-events",
  match = { class = ".*" },
  suppress_event = "maximize",
})

-- Spotlight-style floating launcher panel
hl.window_rule({
  name = "hyprlauncher-spotlight",
  match = { class = "hyprlauncher" },
  float = true,
  center = true,
  rounding = 20,
  opacity = "0.97 override 0.97 override 1.0 override",
})
