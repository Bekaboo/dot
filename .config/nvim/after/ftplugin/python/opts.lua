local cursorline = vim.opt_local.cursorline:get()
local cursorlineopt = vim.opt_local.cursorlineopt:get()
if cursorline and (cursorlineopt == 'both' or cursorlineopt == 'line') then
  vim.opt_local.cursorcolumn = true
end

local tsu = require('utils.ts')

if tsu.active() then
  ---@param trig string
  ---@param expansion string
  ---@return nil
  local function iabbr_normalzone(trig, expansion)
    vim.keymap.set('ia', trig, function()
      return tsu.active()
          and not tsu.in_node('comment')
          and not tsu.in_node('string')
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
