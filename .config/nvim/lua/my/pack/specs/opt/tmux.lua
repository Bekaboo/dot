local load = require('my.utils.load')

---@type my.pack.spec
return {
  src = 'module://my.plugin.tmux',
  data = {
    enabled = not vim.g.vscode and vim.g.has_ui,
    load = load.schedule_wrap(function()
      require('my.plugin.tmux').setup()
    end),
  },
}
