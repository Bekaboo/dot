package.path = table.concat({
  package.path,
  vim.fs.normalize('~/.luarocks/share/lua/5.1/?/init.lua'),
  vim.fs.normalize('~/.luarocks/share/lua/5.1/?.lua'),
}, ';')

require('image').setup({
  backend = 'kitty',
  integrations = {
    markdown = { enabled = false },
    neorg = { enabled = false },
  },
  window_overlap_clear_enabled = true,
  tmux_show_only_in_active_window = true,
  window_overlap_clear_ft_ignore = {},
  max_width = 80,
  max_height = 12,
  max_width_window_percentage = math.huge,
  max_height_window_percentage = math.huge,
})
