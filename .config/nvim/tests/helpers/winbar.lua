local helpers = require('helpers')

local M = {}

---Get the winbar symbols provided by a source at a test point in the current
---buffer
---@param source my.winbar.source
---@param test_point integer
---@return my.winbar.symbol[]
function M.symbols_at(source, test_point)
  return source.get_symbols(
    vim.api.nvim_get_current_buf(),
    vim.api.nvim_get_current_win(),
    helpers.test_point(test_point)
  )
end

---Get the names of winbar symbols provided by a source at a test point in the
---current buffer, e.g. the symbols path shown in the winbar
---@param source my.winbar.source
---@param test_point integer
---@return string[]
function M.symbol_names_at(source, test_point)
  return vim.tbl_map(function(symbol)
    return symbol.name
  end, M.symbols_at(source, test_point))
end

---Build a nested table of the names of the children of a winbar symbol, e.g.
---{ H1 = { H2 = {} } }
---@param symbol my.winbar.symbol
---@return table<string, table>
function M.children_tree(symbol)
  local tree = {}
  for _, child in ipairs(symbol.children or {}) do
    tree[child.name] = M.children_tree(child)
  end
  return tree
end

return M
