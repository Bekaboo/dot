local strategies = vim.g['test#custom_strategies'] or {}

-- Modify & confirm test command before running
strategies.confirm = function(cmd)
  vim.ui.input({ prompt = 'Test command: ', default = cmd }, function(input)
    cmd = input
  end)
  if not cmd then
    return
  end
  return vim.fn['test#strategy#' .. (vim.g['test#confirm#strategy'] or 'basic')](
    cmd
  )
end

vim.g['test#custom_strategies'] = strategies

vim.g['test#strategy'] = 'dispatch'
vim.g['test#confirm#strategy'] = 'dispatch'

-- Lazy-load test configs for each filetype
require('utils.load').ft_auto_load_once('test-configs', function(ft, configs)
  if not configs then
    return false
  end
  -- Vim-test use autoload vim variables, e.g. `g:test#go#gotest#options...`
  -- so we have to first unnest lua table using '#' as delimiter then set
  -- the test global variable.
  -- Also see: https://www.reddit.com/r/neovim/comments/jwd0qx/how_do_i_define_vim_variable_in_lua/
  vim
    .iter(require('utils.lua').unnest({ test = { [ft] = configs } }, '#'))
    :each(function(name, val)
      vim.g[name] = val
    end)
  return true
end)

-- stylua: ignore start
vim.keymap.set('n', '<Leader>tk', '<Cmd>TestClass<CR>',   { desc = 'Run the first test class in current file' })
vim.keymap.set('n', '<Leader>tf', '<Cmd>TestFile<CR>',    { desc = 'Run all tests in current file' })
vim.keymap.set('n', '<Leader>tt', '<Cmd>TestNearest<CR>', { desc = 'Run the test neartest to cursor' })
vim.keymap.set('n', '<Leader>tr', '<Cmd>TestLast<CR>',    { desc = 'Run the last test' })
vim.keymap.set('n', '<Leader>ts', '<Cmd>TestSuite<CR>',   { desc = 'Run the whole test suite' })
vim.keymap.set('n', '<Leader>to', '<Cmd>TestVisit<CR>',   { desc = 'Go to last visited test file' })
-- stylua: ignore end
