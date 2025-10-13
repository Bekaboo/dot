---@type pack.spec
return {
  src = 'https://github.com/scalameta/nvim-metals',
  data = {
    events = {
      event = 'FileType',
      pattern = { 'scala', 'sbt' },
    },
    postload = function()
      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('my.nvim_metals.init', {}),
        pattern = { 'scala', 'sbt' },
        callback = function()
          require('metals').initialize_or_attach(
            require('metals').bare_config()
          )
        end,
      })
    end,
  },
}
