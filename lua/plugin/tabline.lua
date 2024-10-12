local utils = require('utils')
local tabline = {}

function tabline.get()
  local tabnames = {}
  local tabidcur = vim.api.nvim_get_current_tabpage()
  for tabnr, tabid in ipairs(vim.api.nvim_list_tabpages()) do
    table.insert(
      tabnames,
      utils.stl.hl(
        string.format(
          '%%%dT %s %%X',
          tabid,
          vim.fn.fnamemodify(
            vim.fn.getcwd(vim.api.nvim_tabpage_get_win(tabid), tabnr),
            ':.:~'
          )
        ),
        tabid == tabidcur and 'TabLineSel' or 'TabLine'
      )
    )
  end
  return table.concat(tabnames)
end

return tabline
