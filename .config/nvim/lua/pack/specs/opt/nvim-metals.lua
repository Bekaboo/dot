---@type pack.spec
return {
  src = 'https://github.com/scalameta/nvim-metals',
  data = {
    deps = {
      src = 'https://github.com/mfussenegger/nvim-dap',
      data = { optional = true },
    },
    events = {
      event = 'FileType',
      pattern = { 'scala', 'sbt' },
    },
    postload = function()
      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('my.nvim_metals.init', {}),
        pattern = { 'scala', 'sbt' },
        callback = function()
          local metals = require('metals')
          local dap_ok, dap = pcall(require, 'dap')
          local config = metals.bare_config()

          if dap_ok then
            config.on_attach = function()
              metals.setup_dap()
            end
            dap.configurations.scala = {
              {
                type = 'scala',
                request = 'launch',
                name = 'Run or Test Target',
                metals = {
                  runType = 'runOrTestFile',
                },
              },
              {
                type = 'scala',
                request = 'launch',
                name = 'Test Target',
                metals = {
                  runType = 'testTarget',
                },
              },
              {
                type = 'scala',
                request = 'attach',
                name = 'Attach to Localhost',
                hostName = 'localhost',
                port = 5005,
                buildTarget = 'root',
              },
            }
          end

          metals.initialize_or_attach(config)
        end,
      })
    end,
  },
}
