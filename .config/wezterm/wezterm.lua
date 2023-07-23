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
  {
    family = 'Jetbrains Mono Nerd Font',
    weight = 'Light',
  },
  {
    family = 'Times New Roman',
  },
  {
    family = 'Microsoft YaHei',
  },
})
config.font_size = 13.2
config.set_environment_variables = {
  WEZTERM = tostring(wezterm.procinfo.pid()),
}
config.term = 'wezterm'
config.window_padding = {
  left = 0,
  right = 0,
  top = 0,
  bottom = 0,
}

-- theme.toml links to colors/light.toml or colors/dark.toml, which
-- further links to colors/<theme_name>-[light|dark].toml
-- so that we can change the symlinks in a bash script to reload the
-- colorschemes without modifying the config files
local _, metadta = wezterm.color.load_scheme(config_dir .. '/theme.toml')
config.color_scheme = metadta.name

return config
