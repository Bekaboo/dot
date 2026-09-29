-- Shell script formatter for sh/bash/mksh
-- https://github.com/patrickvane/shfmt

local lang_settings = {
  {
    -- If `expandtab` is not set, use tabs for indentation, else use
    -- spaces with the same width in nvim, see `shfmt -h` and
    -- https://github.com/mattn/efm-langserver/blob/master/schema.md#2113-property-format-command
    formatCommand = 'shfmt --keep-padding --filename ${INPUT} --indent=${tabWidth} ${--indent=0:!insertSpaces} -',
    formatStdin = true,
  },
}

---@type my.lsp.config
return {
  filetypes = { 'bash', 'sh' },
  cmd = { 'efm-langserver' },
  requires = { 'shfmt' },
  name = 'shfmt',
  init_options = { documentFormatting = true },
  settings = {
    languages = {
      sh = lang_settings,
      bash = lang_settings,
    },
  },
}
