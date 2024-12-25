local M = {}

---Returns whether treesitter is active in `buf`
---@param buf integer? default: current buffer
---@return boolean
function M.active(buf)
  if not buf or buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  if vim.treesitter.highlighter.active[buf] then
    return true
  end

  -- `vim.treesitter.get_parser()` can be slow for big files
  if not vim.b.bigfile and (pcall(vim.treesitter.get_parser, buf)) then
    return true
  end

  -- File is big or cannot get parser for buf
  return false
end

---Returns whether cursor is in a specific type of treesitter node
---@param ntype string|function(type: string): boolean type of node, or function to check node type
---@param pos integer[]? 1,0-indexed position, default: current cursor position
---@param buf integer? default: current buffer
---@param mode string? default: current mode
---@return boolean
function M.in_node(ntype, pos, buf, mode)
  pos = pos or vim.api.nvim_win_get_cursor(0)
  buf = buf or vim.api.nvim_get_current_buf()
  mode = mode or vim.api.nvim_get_mode().mode
  if not M.active(buf) then
    return false
  end
  local node = vim.treesitter.get_node({
    bufnr = buf,
    pos = {
      pos[1] - 1,
      pos[2] - (pos[2] >= 1 and mode:match('^i') and 1 or 0),
    },
  })
  if not node then
    return false
  end
  if type(ntype) == 'string' then
    return node:type():match(ntype) ~= nil
  end
  return ntype(node:type())
end

return M