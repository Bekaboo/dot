local M = {}

---Set window height, without affecting cmdheight
---@param win integer window ID
---@param height integer window height
---@return nil
function M.win_safe_set_height(win, height)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  local winnr = vim.fn.winnr()
  if vim.fn.winnr('j') ~= winnr or vim.fn.winnr('k') ~= winnr then
    local cmdheight = vim.go.cmdheight
    vim.api.nvim_win_set_height(win, height)
    vim.go.cmdheight = cmdheight
  end
end

---Get current 'effective' lines (lines can be used by normal windows)
---@return integer
function M.effective_lines()
  local lines = vim.go.lines
  local ch = vim.go.ch
  local ls = vim.go.ls
  return lines
    - ch
    - (
      ls == 0 and 0
      or (ls == 2 or ls == 3) and 1
      or (
        #vim.tbl_filter(function(win)
              return vim.fn.win_gettype(win) ~= 'popup'
            end, vim.api.nvim_tabpage_list_wins(0))
            > 1
          and 1
        or 0
      )
    )
end

---Returns a function to save some attributes over a list of windows
---@param save_method fun(win: integer): any?
---@return fun(store: table<integer, any>, wins: integer[]?)
function M.save(save_method)
  ---@param store string|table<integer, any>
  ---@param wins? integer[] list of wins to restore, default to all windows in
  ---current tabpage
  return function(store, wins)
    if type(store) == 'string' then
      store = _G[store]
    end
    if not store then
      return
    end
    for _, win in ipairs(wins or vim.api.nvim_tabpage_list_wins(0)) do
      local ok, result = pcall(vim.api.nvim_win_call, win, function()
        return save_method(win)
      end)
      if ok then
        store[win] = result
      end
    end
  end
end

---Returns a function to restore the attributes of windows from `store`
---@param restore_method fun(win: integer, data: any): any?
---@return fun(store: table<integer, any>, wins: integer[]?)
function M.restore(restore_method)
  ---@param store string|table<integer, any>
  ---@param wins? integer[] list of wins to restore, default to all windows in
  ---current tabpage
  return function(store, wins)
    if type(store) == 'string' then
      store = _G[store]
    end
    if not store then
      return
    end
    for _, win in pairs(wins or vim.api.nvim_tabpage_list_wins(0)) do
      if store[win] then
        if not vim.api.nvim_win_is_valid(win) then
          store[win] = nil
        else
          pcall(vim.api.nvim_win_call, win, function()
            restore_method(win, store[win])
          end)
        end
      end
    end
  end
end

M.save_views = M.save(function(_)
  return vim.fn.winsaveview()
end)

M.restore_views = M.restore(function(_, view)
  vim.fn.winrestview(view)
end)

M.save_heights = M.save(vim.api.nvim_win_get_height)
M.restore_heights = M.restore(M.win_safe_set_height)

---Save window ratios as { height_ratio, width_ratio } tuple
M.save_ratio = M.save(function(win)
  local h = vim.api.nvim_win_get_height(win)
  local w = vim.api.nvim_win_get_width(win)
  return {
    hr = h / M.effective_lines(),
    wr = w / vim.go.columns,
    h = h,
    w = w,
  }
end)

---Restore window ratios, respect &winfixheight and &winfixwidth and keep
---command window height untouched
M.restore_ratio = M.restore(function(win, ratio)
  local hr = type(ratio.hr) == 'table' and ratio.hr[vim.val_idx] or ratio.hr
  local wr = type(ratio.wr) == 'table' and ratio.wr[vim.val_idx] or ratio.wr
  local h = ratio.h
  local w = ratio.w
  local cmdwin = vim.fn.win_gettype() == 'command'

  if not vim.wo.wfh and not cmdwin then
    M.win_safe_set_height(win, vim.fn.round(M.effective_lines() * hr))
  else
    vim.schedule(function()
      M.win_safe_set_height(win, h)
    end)
  end
  if not vim.wo.wfw and not cmdwin then
    vim.api.nvim_win_set_width(win, vim.fn.round(vim.go.columns * wr))
  else
    vim.schedule(function()
      vim.api.nvim_win_set_width(win, w)
    end)
  end
end)

---Check if a window is empty
---A window is considered 'empty' if its containing buffer is empty
---@param win integer? default to current window
---@return boolean
function M.is_empty(win)
  win = win or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then
    return true
  end
  return require('utils.buf').is_empty(vim.api.nvim_win_get_buf(win))
end

return M
