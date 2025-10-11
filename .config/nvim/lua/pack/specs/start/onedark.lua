---@type pack.spec
return {
  src = 'https://github.com/navarasu/onedark.nvim',
  data = {
    postload = function()
      require('utils.hl').persist(function()
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

        vim.api.nvim_set_hl(0, 'WinBar', { link = 'StatusLine' })
        vim.api.nvim_set_hl(0, 'WinBarNC', { link = 'StatusLineNC' })
      end)
    end,
  },
}
