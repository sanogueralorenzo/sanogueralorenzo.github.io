-- Upstream Omarchy owns the desktop; Android owns its display and session.
dofile('/usr/share/omarchy/default/hypr/bootstrap.lua')
package.preload['default.hypr.autostart'] = function()
    hl.on('hyprland.start', function()
        hl.exec_cmd('dbus-update-activation-environment --all')
        hl.exec_cmd('omarchy-launch-shell')
        hl.exec_cmd('omarchy-launch-terminal')
    end)
end
require('default.hypr.omarchy')
require('hypr.input')
require('hypr.bindings')
require('hypr.looknfeel')
require('hypr.autostart')
require('default.hypr.toggles')

hl.monitor({ output = '', mode = 'preferred', position = '0x0', scale = 1.5 })
hl.config({
    decoration = { blur = { enabled = false }, shadow = { enabled = false } },
    animations = { enabled = false },
    cursor = { no_hardware_cursors = true },
})
