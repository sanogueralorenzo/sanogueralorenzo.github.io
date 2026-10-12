-- Amarchy runs Omarchy's desktop defaults inside Android's display surface.
dofile('/usr/share/omarchy/default/hypr/bootstrap.lua')
require('default.hypr.helpers')
require('default.hypr.looknfeel')
require('default.hypr.bindings.tiling')

hl.monitor({ output = '', mode = 'preferred', position = '0x0', scale = 1.5 })
hl.config({
    general = { gaps_in = 5, gaps_out = 8, border_size = 2,
        col = { active_border = 'rgb(7fbbb3)', inactive_border = 'rgb(475258)' } },
    decoration = { rounding = 8, blur = { enabled = false }, shadow = { enabled = false } },
    animations = { enabled = false },
    input = { kb_layout = 'us', repeat_rate = 35, repeat_delay = 300, follow_mouse = 1 },
    misc = { disable_hyprland_logo = true, disable_splash_rendering = true },
    cursor = { no_hardware_cursors = true },
})
o.bind('SUPER + RETURN', 'Terminal', 'foot')
o.bind('SUPER + E', 'Files', 'nautilus --new-window /root')
o.bind('SUPER + B', 'Browser', 'chromium --ozone-platform=wayland --no-sandbox --disable-gpu --no-first-run --no-default-browser-check')
hl.on('hyprland.start', function()
    hl.exec_cmd('dbus-update-activation-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP')
    hl.exec_cmd('foot')
end)
