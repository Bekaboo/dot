local cursorline = vim.opt_local.cursorline:get()
local cursorlineopt = vim.opt_local.cursorlineopt:get()
if cursorline and (cursorlineopt == 'both' or cursorlineopt == 'line') then
  vim.opt_local.cursorcolumn = true
end

local tsu = require('utils.treesitter')

if tsu.is_active() then
  ---@param trig string
  ---@param expansion string
  ---@return nil
  local function iabbr_normalzone(trig, expansion)
    vim.keymap.set('ia', trig, function()
      return tsu.is_active()
          and not tsu.in_tsnode('comment')
          and not tsu.in_tsnode('string')
          and expansion
        or trig
    end, {
      buffer = true,
      expr = true,
    })
  end
  iabbr_normalzone('true', 'True')
  iabbr_normalzone('ture', 'True')
  iabbr_normalzone('false', 'False')
  iabbr_normalzone('flase', 'False')
end
