---@type my.pack.spec
return {
  src = 'module://my.plugin.term',
  data = {
    enabled = not vim.g.vscode,
    events = 'TermOpen',
    postload = function(_, _, args)
      local term = require('my.plugin.term')
      term.setup()
      vim.keymap.set('n', '.', term.rerun, {
        buffer = args.buf,
        desc = 'Re-run terminal job',
      })
    end,
  },
}
