---@type my.pack.spec
return {
  src = 'https://github.com/RRethy/nvim-treesitter-endwise',
  data = {
    events = 'InsertEnter',
    postload = function()
      local endwise = require('nvim-treesitter-endwise')
      local lang = vim.treesitter.language.get_lang(vim.bo.ft)
      if not endwise.is_supported(lang) then
        return
      end

      require('nvim-treesitter.endwise').attach(0)
    end,
  },
}
