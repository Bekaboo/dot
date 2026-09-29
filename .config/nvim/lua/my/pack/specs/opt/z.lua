---@type my.pack.spec
return {
  src = 'module://my.plugin.z',
  data = {
    enabled = not vim.g.vscode,
    events = { 'UIEnter', 'DirChanged' },
    cmds = { 'Z', 'ZSelect' },
    keys = { lhs = '<Leader>z', opts = { desc = 'Open a directory from z' } },
    load = function(spec, path, args)
      local load = function()
        if spec.data and spec.data.postload then
          spec.data.postload(spec, path, args)
        end
      end
      if args and args.event == 'UIEnter' then
        vim.schedule(load)
        return
      end
      load()
    end,
    postload = function()
      local z = require('my.plugin.z')

      z.setup()

      vim.keymap.set(
        'n',
        '<Leader>z',
        z.select,
        { desc = 'Open a directory from z' }
      )
    end,
  },
}
