---@type pack.spec
return {
  src = 'https://github.com/navarasu/onedark.nvim',
  data = {
    postload = function()
      local hl = require('utils.hl')

      hl.persist(function()
        if vim.g.colors_name and vim.g.colors_name ~= 'onedark' then
          return
        end

        require('onedark').setup({
          style = vim.go.background, -- make `set bg=light/dark` work
          diagnostics = {
            darker = false,
          },
        })
        require('onedark').load()

        hl.set(0, 'WinBar', { link = 'StatusLine' })
        hl.set(0, 'WinBarNC', { link = 'StatusLineNC' })
        hl.set(0, 'FloatTitle', { link = 'NormalFloat', fg = 'Title' })
      end)
    end,
  },
}
