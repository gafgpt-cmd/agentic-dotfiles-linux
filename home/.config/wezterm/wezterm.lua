local wezterm = require("wezterm")

local config = wezterm.config_builder()

config.color_scheme = "rose-pine-moon"
config.font = wezterm.font("Hack Nerd Font")
config.font_size = 15.0
config.window_background_opacity = 0.8
config.macos_window_background_blur = 50
config.hide_tab_bar_if_only_one_tab = true
config.window_decorations = "RESIZE"

-- Emit Esc as an atomic key event (\x1b[27u) so Herdr can't fold a lone
-- Escape into a tailgating mouse event and swallow it in editors like Neovim.
config.enable_kitty_keyboard = true

return config
