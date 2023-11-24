local wezterm = require('wezterm')
local config = wezterm.config_builder and wezterm.config_builder() or {}
local config_dir = wezterm.config_dir

config.automatically_reload_config = true
config.animation_fps = 1 -- Disable cursor blinking easing animation
config.color_scheme_dirs = { config_dir .. '/colors' }
config.color_scheme = 'Nano Dark' -- Default colorscheme
config.check_for_updates = false
config.enable_tab_bar = false
config.font = wezterm.font_with_fallback({
  { family = 'Jetbrains Mono NF', weight = 'Light' },
  { family = 'Times New Roman' },
  { family = 'Microsoft YaHei' },
})
config.font_size = 13.2
config.term = 'wezterm'
config.window_padding = {
  left = '1cell',
  right = '1cell',
  top = '0.5cell',
  bottom = '0.5cell',
}

-- theme.toml links to colors/light.toml or colors/dark.toml, which
-- further links to colors/<theme_name>-[light|dark].toml
-- so that we can change the symlinks in a bash script to reload the
-- colorschemes without modifying the config files
local _, metadata = wezterm.color.load_scheme(config_dir .. '/theme.toml')
config.color_scheme = metadata.name

return config
