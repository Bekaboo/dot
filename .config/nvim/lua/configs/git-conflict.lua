---@diagnostic disable-next-line: missing-fields
require('git-conflict').setup({
  default_mappings = {
    ours = 'c<',
    theirs = 'c>',
    none = 'c-',
    both = 'c=',
    next = ']x',
    prev = '[x',
  },
})
