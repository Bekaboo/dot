require('my.plugin.readline').setup()

---Trigger an insert mode keymap on a single line of the current buffer
---@param lhs string keymap to trigger, e.g. `<C-w>`
---@param line string buffer content before the keymap runs
---@param col integer byte offset of the cursor in `line`
---@return string line content after the keymap ran
---@return string `-` register content after the keymap ran
local function press(lhs, line, col)
  -- `small_del()` releases the lock from a scheduled autocmd callback that
  -- never runs in a spec, clear it here to keep the cases independent
  vim.g._rl_del_lock = nil
  vim.fn.setreg('-', '')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  vim.api.nvim_win_set_cursor(0, { 1, col })
  -- 'x' executes the keys before `nvim_feedkeys()` returns
  vim.api.nvim_feedkeys(vim.keycode('i' .. lhs), 'x', false)
  return vim.api.nvim_get_current_line(), vim.fn.getreg('-')
end

describe('[plugin][readline]', function()
  -- Repeated `<Left>`/`<Right>`/`<Del>` must count characters, so a 3 byte
  -- character still takes one key press, otherwise the deletion runs past the
  -- text it targets, e.g. `<C-w>` on "中文测试中文" would leave "中文"
  local cases = {
    {
      desc = '<C-u> deletes the cjk text before the cursor',
      lhs = '<C-u>',
      line = '  中文',
      col = 5,
      after = '  文',
      deleted = '中',
    },
    {
      desc = '<C-w> deletes the cjk word before the cursor',
      lhs = '<C-w>',
      line = '中文测试中文',
      col = 6,
      after = '测试中文',
      deleted = '中文',
    },
    {
      desc = '<M-d> deletes the cjk word after the cursor',
      lhs = '<M-d>',
      line = '中文 abc',
      col = 0,
      after = ' abc',
      deleted = '中文',
    },
    {
      desc = '<C-k> deletes the cjk text after the cursor',
      lhs = '<C-k>',
      line = '中文测试中文',
      col = 6,
      after = '中文',
      deleted = '测试中文',
    },
    {
      desc = '<C-u> deletes the text before the cursor',
      lhs = '<C-u>',
      line = 'abc def',
      col = 4,
      after = 'def',
      deleted = 'abc ',
    },
    {
      desc = '<C-w> deletes the word before the cursor',
      lhs = '<C-w>',
      line = 'abc def',
      col = 4,
      after = 'def',
      deleted = 'abc ',
    },
    {
      desc = '<M-d> deletes the word after the cursor',
      lhs = '<M-d>',
      line = 'abc def',
      col = 0,
      after = ' def',
      deleted = 'abc',
    },
  }

  for _, case in ipairs(cases) do
    it(case.desc, function()
      local line, deleted = press(case.lhs, case.line, case.col)
      assert.are.same(case.after, line)
      assert.are.same(case.deleted, deleted)
    end)
  end
end)
