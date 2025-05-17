local wezterm = require('wezterm')
local config = wezterm.config_builder and wezterm.config_builder() or {}
local config_dir = wezterm.config_dir

config.automatically_reload_config = true
config.animation_fps = 1 -- Disable cursor blinking easing animation
config.check_for_updates = false
config.enable_tab_bar = false

-- Use both left+right option key as alt on macOS
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false

config.font_size = 12
config.font = wezterm.font_with_fallback({
  { family = 'Iosevka' },
  { family = 'Microsoft YaHei' },
})

config.initial_rows = 24
config.initial_cols = 112
config.window_padding = {
  left = '1cell',
  right = '1cell',
  top = '0.5cell',
  bottom = '0.5cell',
}

config.color_scheme_dirs = { config_dir .. '/colors' }

---`theme.toml` links to `colors/light.toml` or `colors/dark.toml`, which
---further links to `colors/<theme_name>-[light|dark].toml`
---so that we can change the symlinks in a bash script to reload the
---colorschemes without modifying the config files
---@param theme string
local function load_theme_file(theme)
  local _, metadata =
    wezterm.color.load_scheme(('%s/%s.toml'):format(config_dir, theme))
  if metadata and metadata.name then
    config.color_scheme = metadata.name
  end
end

---Get current system background
---See: https://wezterm.org/config/lua/wezterm.gui/get_appearance.html
---@return 'light'|'dark'
local function get_bg()
  if wezterm.gui then
    return wezterm.gui.get_appearance():lower()
  end
  return 'dark'
end

-- Default themes
load_theme_file('colors/macro-dark')
load_theme_file('colors/dark')
load_theme_file('theme')

-- Load theme based on system background
load_theme_file('colors/' .. get_bg())

-- macOS-specific overrides, see:
-- https://wezterm.org/config/lua/wezterm/target_triple.html
if wezterm.target_triple:match('darwin') then
  config.font_size = 14
end

return config
