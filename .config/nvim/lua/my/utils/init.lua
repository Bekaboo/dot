---@diagnostic disable: assign-type-mismatch

return setmetatable({
  buf = nil, ---@module 'my.utils.buf'
  cmd = nil, ---@module 'my.utils.cmd'
  dap = nil, ---@module 'my.utils.dap'
  fs = nil, ---@module 'my.utils.fs'
  git = nil, ---@module 'my.utils.git'
  hl = nil, ---@module 'my.utils.hl'
  json = nil, ---@module 'my.utils.json'
  key = nil, ---@module 'my.utils.key'
  keys = nil, ---@module 'my.utils.keys'
  load = nil, ---@module 'my.utils.load'
  lsp = nil, ---@module 'my.utils.lsp'
  lua = nil, ---@module 'my.utils.lua'
  opt = nil, ---@module 'my.utils.opt'
  opts = nil, ---@module 'my.utils.opts'
  pack = nil, ---@module 'my.utils.pack'
  snippets = nil, ---@module 'my.utils.snip'
  static = nil, ---@module 'my.utils.static'
  stl = nil, ---@module 'my.utils.stl'
  str = nil, ---@module 'my.utils.str'
  syn = nil, ---@module 'my.utils.syn'
  tab = nil, ---@module 'my.utils.tab'
  term = nil, ---@module 'my.utils.term'
  term_t = nil, ---@module 'my.utils.term_t'
  test = nil, ---@module 'my.utils.test'
  ts = nil, ---@module 'my.utils.ts'
  web = nil, ---@module 'my.utils.web'
  win = nil, ---@module 'my.utils.win'
}, {
  __index = function(_, key)
    return require('my.utils.' .. key)
  end,
})
