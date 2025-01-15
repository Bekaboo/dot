local utils = require('utils')

_G._tabline = {}

setmetatable(_G._tabline, {
  ---@return string
  __call = function()
    local tabnames = {}
    local tabidcur = vim.api.nvim_get_current_tabpage()
    for tabnr, tabid in ipairs(vim.api.nvim_list_tabpages()) do
      -- Tab names are saved in global variables by number instead of id
      -- because tab ids are not preserved across sessions
      -- If tab-local tab name variable is not set but a global tab name
      -- variable exists for that tab, restore the tab-local tab name using
      -- the global tab name variable; else save the tab-local name variable
      -- to the corresponding global variable
      local tabname_id = vim.t[tabid]._tabname
      local tabname_nr = vim.g['Tabname' .. tabnr]
      if tabname_id and tabname_id ~= tabname_nr then
        vim.g['Tabname' .. tabnr] = tabname_id
      elseif not tabname_id and tabname_nr then
        vim.t[tabid]._tabname = tabname_nr
      end
      table.insert(
        tabnames,
        utils.stl.hl(
          string.format(
            '%%%dT %s %%X',
            tabnr,
            vim.t[tabid]._tabname
              or vim.fn.pathshorten(
                vim.fn.fnamemodify(
                  vim.fn.getcwd(vim.api.nvim_tabpage_get_win(tabid), tabnr),
                  ':.:~'
                )
              )
          ),
          tabid == tabidcur and 'TabLineSel' or 'TabLine'
        )
      )
    end
    return table.concat(tabnames)
  end,
})

---@param tabid integer?
---@param name string?
---@return nil
function _G._tabline.rename(tabid, name)
  if not tabid or not vim.api.nvim_tabpage_is_valid(tabid) then
    return
  end
  vim.t[tabid]._tabname = name
  for nr, id in ipairs(vim.api.nvim_list_tabpages()) do
    if tabid == id then
      vim.g['Tabname' .. nr] = name
      break
    end
  end
  vim.cmd.redrawtabline()
end

-- `:[count]TabRename [name]`
-- 1. `[count]` works like `:[count]tabnew`
-- 2. When `[name]` is omitted, fallback to default name (cwd)
vim.api.nvim_create_user_command('TabRename', function(opts)
  _G._tabline.rename(
    opts.count == -1 and vim.api.nvim_get_current_tabpage()
      or vim.api.nvim_list_tabpages()[opts.count],
    opts.fargs[1]
  )
end, {
  nargs = '?',
  count = -1,
  addr = 'tabs',
  desc = 'Rename the current tab.',
})

-- Preserve tab names across sessions
vim.opt.sessionoptions:append('globals')

vim.api.nvim_create_autocmd('TabClosed', {
  desc = 'Clear global tab name variable for closed tabs.',
  group = vim.api.nvim_create_augroup('Tabline', {}),
  callback = function(info)
    vim.g['Tabname' .. info.file] = nil
  end,
})

return _G._tabline
