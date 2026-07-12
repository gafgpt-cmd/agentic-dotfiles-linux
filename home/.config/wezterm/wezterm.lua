local wezterm = require("wezterm")

local config = wezterm.config_builder()

config.color_scheme = "rose-pine-moon"
config.font = wezterm.font("Hack Nerd Font")
config.font_size = 15.0
config.window_background_opacity = 0.8
config.macos_window_background_blur = 50
config.hide_tab_bar_if_only_one_tab = true
config.window_decorations = "RESIZE"

-- With Herdr mouse_capture=false, the Herdr client is a full-screen alt-screen app
-- enabling no mouse reporting, so WezTerm would otherwise synthesize Up/Down arrow
-- keys for wheel scroll (default speed 3) and a pane REPL reads them as history
-- navigation. Set to 0 so wheel input in alternate-screen apps is never turned into
-- arrow keys. Scroll pane scrollback with PageUp/PageDown or copy-mode (prefix+y).
config.alternate_buffer_wheel_scroll_speed = 0

return config
