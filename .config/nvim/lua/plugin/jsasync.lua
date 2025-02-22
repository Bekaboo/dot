---Automatically add 'async' to functions containing 'await'
---Source: https://gist.github.com/JoosepAlviste/43e03d931db2d273f3a6ad21134b3806

---When typing 'await' add 'async' to the function declaration if the function
---isn't async already.
local function add_async()
  if
    vim.v.char ~= 't'
    or not vim.endswith(
      vim.api.nvim_get_current_line():sub(1, vim.fn.col('.') - 1),
      'awai'
    )
  then
    return
  end

  local ts = require('utils.ts')
  local lang = ts.lang()
  if
    not lang or not lang:find('javascript') and not lang:find('typescript')
  then
    return
  end

  -- `ignore_injections = false` makes this snippet work in filetypes where JS
  -- is injected into other languages
  local func_node = ts.find_node(
    { 'function', 'method' },
    { ignore_injections = false }
  )
  if not func_node then
    return
  end

  if vim.startswith(vim.treesitter.get_node_text(func_node, 0), 'async') then
    return
  end

  local start_row, start_col = func_node:start()
  vim.schedule(function()
    vim.api.nvim_buf_set_text(
      0,
      start_row,
      start_col,
      start_row,
      start_col,
      { 'async ' }
    )
  end)
end

---Plugin setup function
local function setup()
  if vim.g.loaded_jsasync ~= nil then
    return
  end
  vim.g.loaded_jsasync = true

  vim.api.nvim_create_autocmd('InsertCharPre', {
    group = vim.api.nvim_create_augroup('JSAsync', {}),
    callback = add_async,
  })
end

return { setup = setup }
