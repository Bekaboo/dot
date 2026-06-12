local M = {}

---Setup input method auto switch
---@return nil
function M.setup()
  if vim.g.loaded_im ~= nil then
    return
  end
  vim.g.loaded_im = true

  if vim.env.SSH_TTY then
    return
  end

  local backend = require('my.plugin.im.backends').detect()
  if not backend then
    return
  end

  -- This is how it works:
  -- - vim.b[{buf}]._im_restore is set when the input method is temporarily
  --   disabled for the buffer {buf} and should be restored when entering
  --   'input modes' (*).
  -- - vim.g._im_input_enter records the last buffer where we entered
  --   'input modes'.
  --
  -- When we enter 'input modes', flag `vim.g._im_input_enter` is set to
  -- `<abuf>`, and if `_im_restore` is set for `<abuf>`, we clear it and
  -- restore/activate the input method.
  --
  -- When we leave 'input modes', we check if input method is activated, and if
  -- so, we disable it and set `_im_restore` for buffer recorded in
  -- `_im_input_enter`. Notice that `_im_input_enter` is not necessarily the
  -- same as `<abuf>` or current buffer, e.g. when we enter an normal buffer in
  -- a normal window from a terminal buffer in terminal window using a key
  -- mapped to `<Cmd>wincmd h/j/k/l/...<CR>`, we switch to non-input mode
  -- (normal mode) from input mode (terminal mode) AFTER entering the normal
  -- buffer, however, we want to set `_im_restore` flag for the terminal
  -- buffer instead of the current (normal) buffer. That's why we need to
  -- keep track of the last buffer where we entered 'input modes' in
  -- `_im_input_enter`.
  --
  -- (*) 'input modes' are modes where the input method should be activated,
  -- including insert mode, replace mode, terminal mode, select mode, and
  -- command mode when command type is '/', '?', '@', or '-'.
  -- Notice that command mode when command type is ':', '>', or '=' is not
  -- considered as input modes, because in these cases one will not want to
  -- insert CJK, even if the input method is activated in the current buffer.

  local buf = vim.api.nvim_get_current_buf()
  backend:on_input_leave(buf)
  backend:on_input_enter(buf)

  local groupid = vim.api.nvim_create_augroup('IMSwitch', {})
  vim.api.nvim_create_autocmd('ModeChanged', {
    desc = 'Try to re-activate input method when entering input modes.',
    group = groupid,
    pattern = '*:[ictRss\x13]*',
    callback = function(info)
      backend:on_input_enter(info.buf)
    end,
  })
  vim.api.nvim_create_autocmd('ModeChanged', {
    desc = 'Deactivate input method when leaving input modes.',
    group = groupid,
    pattern = '[ictRss\x13]*:*',
    callback = function(info)
      backend:on_input_leave(info.buf)
    end,
  })
end

return M
