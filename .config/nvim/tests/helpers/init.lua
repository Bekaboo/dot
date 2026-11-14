local M = {}

---Directory of the test suite
M.tests_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')

---Directory of test assets
M.assets_dir = vim.fs.joinpath(M.tests_dir, 'assets')

---Edit a test asset in the current window
---@param name string file name under `tests/assets`
---@return nil
function M.edit_asset(name)
  vim.cmd.edit(vim.fs.joinpath(M.assets_dir, name))
end

---Get the location of a test point in the current buffer
---
---A test point is a marker in the form of `TESTPOINT<n>` in the buffer, used
---to assert on the context of a specific position without hard coding line
---and column numbers.
---@param test_point integer
---@return integer[] { lnum, col } 1,0-indexed
function M.test_point(test_point)
  local marker = 'TESTPOINT' .. test_point
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    local col = line:find(marker, 1, true)
    if col then
      return { lnum, col - 1 }
    end
  end
  error(('marker %s not found in buffer'):format(marker))
end

return M
