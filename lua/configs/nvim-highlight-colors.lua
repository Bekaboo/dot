local ffi = require('ffi')
local nhc = require('nvim-highlight-colors')

ffi.cdef([[
  typedef struct {} Error;
  typedef struct {} win_T;
  typedef int32_t linenr_T;

  win_T *find_window_by_handle(int Window, Error *err);
  bool hasAnyFolding(win_T *win);
  bool hasFolding(win_T *win, linenr_T lnum,
                  linenr_T *firstp, linenr_T *lastp);
]])

---Highlight visible colors within specified buffer id
local _highlight_colors = nhc.highlight_colors

---Hijack original `highlight_colors()` to apply highlighting only to unfolded
---lines, significantly improving performance when large folds are present in
---visible range
---@param min_row number
---@param max_row number
---@param buf number
---@return nil
function nhc.highlight_colors(min_row, max_row, buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    return -- buffer not visible
  end

  local wp = ffi.C.find_window_by_handle(win, ffi.new('Error'))
  if not vim.wo[win].foldenable or not ffi.C.hasAnyFolding(wp) then
    _highlight_colors(min_row, max_row, buf)
    return
  end

  local unfolded_start, unfolded_end ---@type integer?
  local fold_lastp = ffi.new('linenr_T[1]')
  local linenr = min_row
  while linenr <= max_row do
    if not ffi.C.hasFolding(wp, linenr, nil, fold_lastp) then
      unfolded_start = unfolded_start or linenr
      unfolded_end = linenr
      linenr = linenr + 1
      goto continue
    end

    -- If has folding at `linenr`, next unfolded (visible) line
    -- must at least be the next line of the last folded line
    linenr = fold_lastp[0] + 1
    if unfolded_start and unfolded_end then
      _highlight_colors(unfolded_start, unfolded_end, buf)
      unfolded_start, unfolded_end = nil, nil
    end
    ::continue::
  end

  if unfolded_start and unfolded_end then
    _highlight_colors(unfolded_start, unfolded_end, buf)
  end
end

nhc.setup({
  enable_tailwind = true,
})
