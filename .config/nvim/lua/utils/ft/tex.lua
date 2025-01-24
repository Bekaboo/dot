local M = {}

---Returns whether the cursor is in a math zone
---@return boolean
function M.in_mathzone()
  if vim.b.current_syntax and vim.b.vimtex_id then
    return vim.F.npcall(vim.api.nvim_eval, 'vimtex#syntax#in_mathzone()') == 1
  end

  return require('utils.ts').in_node(
    { 'formula', 'equation', 'math' },
    { ignore_injections = false }
  )
end

---Returns whether the cursor is in normal zone (not in math zone)
---@return boolean
function M.in_normalzone()
  return not M.in_mathzone()
end

return M
