---Automatically add 'async' to functions containing 'await'
---Source: https://gist.github.com/JoosepAlviste/43e03d931db2d273f3a6ad21134b3806

---When typing 'await' add 'async' to the function declaration if the function
---isn't async already.
local function add_async()
  -- This function should be executed when the user types 't' in insert mode,
  -- but 't' is not inserted because it's the trigger.
  vim.api.nvim_feedkeys('t', 'nt', true)

  if
    not vim.endswith(
      vim.api.nvim_get_current_line():sub(1, vim.fn.col('.') - 1),
      'awai'
    )
  then
    return
  end

  -- `ignore_injections = false` makes this snippet work in filetypes where JS
  -- is injected into other languages
  local func_node = require('utils.ts').find_node(
    { 'function', 'method' },
    { ignore_injections = true }
  )
  if not func_node then
    return
  end

  if vim.startswith(vim.treesitter.get_node_text(func_node, 0), 'async') then
    return
  end

  local start_row, start_col = func_node:start()
  vim.api.nvim_buf_set_text(
    0,
    start_row,
    start_col,
    start_row,
    start_col,
    { 'async ' }
  )
end

vim.keymap.set('i', 't', add_async, { buffer = true })
