require('ts-autotag').setup()

local ts_ok, ts_configs = pcall(require, 'nvim-treesitter.configs')
if ts_ok then
  ---@diagnostic disable-next-line: missing-fields
  ts_configs.setup({
    ensure_installed = {
      'xml',
      'html',
    },
  })
end
