hl.window_rule({
  name = "suppress-maximize-events",
  match = { class = ".*" },
  suppress_event = "maximize",
})

hl.window_rule({
  match = { class = "^org.pwmt.zathura$" },
  float = true,
  size = "750 1000",
})
hl.window_rule({
  match = { class = "^blueman-manager$" },
  float = true,
  size = "500 300",
  center = true,
  rounding = 10,
  opacity = "0.90 0.90",
  border_size = 1,
  animation = "popin",
  dim_around = true,
})
hl.window_rule({
  match = { class = "^nm-connection-editor$" },
  float = true,
  size = "500 600",
  center = true,
  rounding = 10,
  opacity = "0.95 0.95",
})
hl.window_rule({
  match = { class = "^xdg-desktop-portal-gtk$" },
  float = true,
  center = true,
  size = "700 400",
})

local portals = {
  "^(xdg-desktop-portal-gtk|xdg-desktop-portal-kde|xdg-desktop-portal-hyprland|org.freedesktop.impl.portal.desktop.gtk|org.freedesktop.impl.portal.desktop.kde)$",
  "^(org.kde.polkit-kde-authentication-agent-1|polkit-gnome-authentication-agent-1|lxqt-policykit-agent|mate-polkit)$",
  "^(pinentry|pinentry-gtk-2|pinentry-gnome3|gcr-prompter)$",
  "^(ssh-askpass|sshaskpass)$",
}
for _, p in ipairs(portals) do
  hl.window_rule({ match = { class = p }, tag = "portal-ui" })
end
hl.window_rule({
  match = { tag = "portal-ui" },
  float = true,
  center = true,
  rounding = 10,
  size = "1100 750",
  dim_around = true,
  opacity = "0.95 0.95",
})

local dialog_titles = {
  "^(Open File)(.*)$",
  "^(Select a File)(.*)$",
  "^(Choose wallpaper)(.*)$",
  "^(Open Folder)(.*)$",
  "^(Save As)(.*)$",
  "^(Library)(.*)$",
  "^(File Upload)(.*)$",
  "^(Extract archive)$",
  "^(Extract)(.*)$",
  "^(Extract to)$",
  "^(Confirm to replace files)$",
  "^(Rename)(.*)$",
  "^(Create New Folder)$",
  "^(Properties)$",
  "^(File Operation Progress)(.*)$",
  "^(app-launcher)$",
}
for _, t in ipairs(dialog_titles) do
  hl.window_rule({ match = { title = t }, float = true, center = true })
end

hl.window_rule({ match = { title = "^(app-launcher)$" }, size = "1200 600", animation = "slide" })
hl.window_rule({ match = { title = "^(Open File)(.*)$" }, size = "900 600", dim_around = true })
hl.window_rule({ match = { title = "^(Save As)(.*)$" }, size = "900 600", dim_around = true })
hl.window_rule({ match = { title = "^(File Upload)(.*)$" }, size = "900 600" })
hl.window_rule({ match = { title = "^(Confirm to replace files)$" }, size = "500 300", dim_around = true })
hl.window_rule({ match = { title = "^(File Operation Progress)(.*)$" }, size = "500 300" })
hl.window_rule({ match = { title = "^(Rename)(.*)$" }, size = "450 200" })
hl.window_rule({ match = { title = "^(Create New Folder)$" }, size = "450 200" })
hl.window_rule({ match = { title = "^(Properties)$" }, size = "500 600" })
hl.window_rule({ match = { modal = true }, float = true, center = true, rounding = 10 })

-- Citrix Workspace: keep the ICA session fully opaque on XWayland
hl.window_rule({
  match = { class = "^(Wfica|Wfica_Seamless|selfservice|Adapter)$" },
  opacity = "1.0 1.0",
  rounding = 0,
})
-- SAML/Entra WebKit dialog. Tiling + focus_on_activate closes it as cancel.
hl.window_rule({
  match = { class = "^(PrimaryAuthManager|AuthManagerDaemon|UtilDaemon)$" },
  float = true,
  center = true,
  pin = true,
  stay_focused = true,
  dim_around = true,
  opacity = "1.0 1.0",
  rounding = 0,
  size = "960 720",
})
hl.window_rule({
  match = { class = "^selfservice$" },
  focus_on_activate = false,
})

-- Zoom VDI plugin Settings is a local Qt window; pin it above fullscreen wfica.
hl.window_rule({
  match = { class = "^(zoom|Zoom)$" },
  float = true,
  center = true,
  pin = true,
})
