local vars = require("vars")
local mainMod = vars.mainMod
local alt = "ALT"
local terminal = vars.terminal
local fileManager = vars.fileManager
local browser = vars.browser
local home = os.getenv("HOME") or "/home/surya"
local scripts = home .. "/.config/hypr/scripts"
local qs = scripts .. "/qs_manager.sh"
local lock = scripts .. "/lock.sh"
local shot = scripts .. "/screenshot.sh"

-- Launcher / hub (Serpantinum replacements for rofi + surface-dots hub)
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd("bash " .. qs .. " toggle applauncher"))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("bash " .. qs .. " toggle settings"))

-- Apps
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("hyprpicker -a"))

-- Window actions
hl.bind(mainMod .. " + X", hl.dsp.window.close())
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + F", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + " .. alt .. " + F", function()
  hl.dispatch(hl.dsp.window.float({ action = "set" }))
  hl.dispatch(hl.dsp.window.resize({ x = 900, y = 600 }))
  hl.dispatch(hl.dsp.window.center())
end)
hl.bind(mainMod .. " + M", function()
  hl.dispatch(hl.dsp.window.fullscreen())
end)
hl.bind(mainMod .. " + DOWN", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + UP", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + G", hl.dsp.group.toggle())

hl.bind(mainMod .. " + L", function()
  hl.dispatch(hl.dsp.window.float({ action = "set" }))
  hl.dispatch(hl.dsp.window.resize({ exact = true, x = 1440, y = 1080 }))
end)

hl.bind(mainMod .. " + CTRL + left", hl.dsp.group.prev())
hl.bind(mainMod .. " + CTRL + right", hl.dsp.group.next())

hl.bind(mainMod .. " + " .. alt .. " + F4", hl.dsp.exec_cmd("hyprctl dispatch 'hl.dsp.exit()'"))
hl.bind(alt .. " + F4", hl.dsp.window.close())

-- Focus
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + SHIFT + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + down", hl.dsp.focus({ direction = "down" }))

hl.bind(mainMod .. " + SHIFT + left", hl.dsp.window.swap({ direction = "l" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.swap({ direction = "r" }))

-- Scratchpad
hl.bind(mainMod .. " + H", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + H", hl.dsp.window.move({ workspace = "special:magic" }))

-- Workspaces 1-10 (close Serpantinum overlays first)
for i = 1, 10 do
  local key = tostring(i % 10)
  hl.bind(mainMod .. " + " .. key, function()
    hl.exec_cmd("bash " .. qs .. " close")
    hl.dispatch(hl.dsp.focus({ workspace = i }))
  end)
  hl.bind(mainMod .. " + SHIFT + " .. key, function()
    hl.exec_cmd("bash " .. qs .. " close")
    hl.dispatch(hl.dsp.window.move({ workspace = i }))
  end)
end

-- Mouse
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Media / brightness
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("swayosd-client --brightness lower"), { locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("swayosd-client --brightness raise"), { locked = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("swayosd-client --output-volume raise"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("swayosd-client --output-volume lower"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("swayosd-client --output-volume mute-toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("swayosd-client --input-volume mute-toggle"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

-- Screenshots (Win+Shift+S region snip; Print opens Serpantinum overlay)
hl.bind(
  mainMod .. " + SHIFT + S",
  hl.dsp.exec_cmd("hyprshot -m region --freeze -o '" .. home .. "/Pictures/Screenshots'"),
  { locked = true }
)
hl.bind("Print", hl.dsp.exec_cmd(shot), { locked = true })
hl.bind(mainMod .. " + Print", hl.dsp.exec_cmd(shot .. " --full"), { locked = true })
hl.bind(mainMod .. " + SHIFT + Print", hl.dsp.exec_cmd(shot .. " --full --edit"), { locked = true })
hl.bind(mainMod .. " + O", hl.dsp.exec_cmd(shot .. " --edit"), { locked = true })

-- Lock (Super+L stays the 1440x1080 float from the old map)
hl.bind("XF86PowerOff", hl.dsp.exec_cmd("bash " .. lock), { locked = true })
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.exec_cmd("bash " .. lock), { locked = true })

-- Serpantinum panels on keys the old map did not use
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("bash " .. qs .. " toggle clipboard"))
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("bash " .. qs .. " toggle wallpaper"))
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("bash " .. qs .. " toggle network"))
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("bash " .. qs .. " toggle volume"))
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd("bash " .. qs .. " toggle calendar"))
hl.bind(mainMod .. " + SHIFT + T", hl.dsp.exec_cmd("bash " .. qs .. " toggle focustime"))

-- Monitor toggles
hl.bind(mainMod .. " + F1", hl.dsp.exec_cmd("bash ~/.config/hypr/toggle-laptop.sh"))
hl.bind(mainMod .. " + F2", hl.dsp.exec_cmd("bash ~/.config/hypr/toggle-monitor.sh"))
