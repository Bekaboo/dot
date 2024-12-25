if vim.g.loaded_coplilot then
  return
end
vim.g.loaded_coplilot = true

require('copilot').setup({
  suggestion = {
    auto_trigger = true,
    keymap = {
      accept = false,
    },
  },
  filetypes = {
    markdown = false,
    text = false,
    tex = false,
    [''] = false,
  },
})

vim.defer_fn(function()
  local suggestion = require('copilot.suggestion')
  local keymap = require('utils.keymap')
  keymap.amend('i', '<C-f>', function(fallback)
    if suggestion.is_visible() then
      suggestion.accept()
    else
      fallback()
    end
  end, { desc = '[copilot] accept suggestion' })
  keymap.amend('i', '<M-f>', function(fallback)
    if suggestion.is_visible() then
      suggestion.accept_word()
    else
      fallback()
    end
  end, { desc = '[copilot] accept suggestion (word)' })
end, 10)

local copilot_util = require('copilot.util')
local _should_attach = copilot_util.should_attach

---Do not attach copilot to large files
---@diagnostic disable-next-line: duplicate-set-field
function copilot_util.should_attach(...)
  if vim.b.bigfile then
    return false
  end
  return _should_attach(...)
end
