---Setup input method (fcitx5) auto switch
---@return nil
local function setup()
  if vim.g.loaded_fcitx5 ~= nil then
    return
  end
  vim.g.loaded_fcitx5 = true

  if
    vim.env.SSH_TTY
    or vim.uv.os_uname().sysname:match('nix$') and not vim.g.display
  then
    return
  end

  local fcitx_cmd = vim.fn.executable('fcitx5-remote') == 1 and 'fcitx5-remote'
    or vim.fn.executable('fcitx-remote') == 1 and 'fcitx-remote'
  if not fcitx_cmd then
    return
  end

  -- This is how it works:
  -- - vim.b[{buf}].__im_restore is set when the input method is temporarily
  --   disabled for the buffer {buf} and should be restored when entering
  --   'input modes' (*).
  -- - vim.g.__im_input_enter records the last buffer where we entered
  --   'input modes'.
  --
  -- When we enter 'input modes', flag `vim.g.__im_input_enter` is set to
  -- `<abuf>`, and if `__im_restore` is set for `<abuf>`, we clear it and
  -- restore/activate the input method.
  --
  -- When we leave 'input modes', we check if input method is activated, and if
  -- so, we disable it and set `__im_restore` for buffer recorded in
  -- `__im_input_enter`. Notice that `__im_input_enter` is not necessarily the
  -- same as `<abuf>` or current buffer, e.g. when we enter an normal buffer in
  -- a normal window from a terminal buffer in terminal window using a key
  -- mapped to `<Cmd>wincmd h/j/k/l/...<CR>`, we switch to non-input mode
  -- (normal mode) from input mode (terminal mode) AFTER entering the normal
  -- buffer, however, we want to set `__im_restore` flag for the terminal
  -- buffer instead of the current (normal) buffer. That's why we need to
  -- keep track of the last buffer where we entered 'input modes' in
  -- `__im_input_enter`.
  --
  -- (*) 'input modes' are modes where the input method should be activated,
  -- including insert mode, replace mode, terminal mode, select mode, and
  -- command mode when command type is '/', '?', '@', or '-'.
  -- Notice that command mode when command type is ':', '>', or '=' is not
  -- considered as input modes, because in these cases one will not want to
  -- insert CJK, even if the input method is activated in the current buffer.

  ---Check if we are in 'input modes'.
  ---@return boolean
  local function inside_input_mode()
    local mode = vim.fn.mode()
    return (
      mode:find('^[itRss\x13]')
      or mode:find('^c') and vim.fn.getcmdtype():find('[/?@-]')
    )
        and true
      or false
  end

  ---Callback to invoke when (possibly) enter input mode
  ---@param buf integer buffer handler
  ---@return nil
  local function input_mode_enter_callback(buf)
    if not inside_input_mode() then
      return
    end
    vim.g.__im_input_enter = buf
    if vim.b[buf].__im_restore then
      vim.b[buf].__im_restore = nil
      vim.system({ fcitx_cmd, '-o' })
    end
  end

  ---Callback to invoke when (possibly) leave input mode
  ---@param buf integer handler
  ---@return nil
  local function input_mode_leave_callback(buf)
    if inside_input_mode() then
      return
    end
    vim.system({ fcitx_cmd }, {}, function(obj)
      if obj.code ~= 0 or tonumber(obj.stdout) == 2 then
        vim.system({ fcitx_cmd, '-c' })
        -- `vim.g.__im_input_enter` may not be set, in which case it
        -- should just be the current buffer
        vim.g.__im_input_enter = vim.g.__im_input_enter or buf
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(vim.g.__im_input_enter) then
            vim.b[vim.g.__im_input_enter].__im_restore = true
          end
        end)
      end
    end)
  end

  local current_buf = vim.api.nvim_get_current_buf()
  input_mode_leave_callback(current_buf)
  input_mode_enter_callback(current_buf)

  local groupid = vim.api.nvim_create_augroup('IMSwitch', {})
  vim.api.nvim_create_autocmd('ModeChanged', {
    desc = 'Try re-activate input method when entering input modes.',
    group = groupid,
    pattern = '*:[ictRss\x13]*',
    callback = function(info)
      input_mode_enter_callback(info.buf)
    end,
  })
  vim.api.nvim_create_autocmd('ModeChanged', {
    desc = 'Deactivate input method when leaving input modes.',
    group = groupid,
    pattern = '[ictRss\x13]*:*',
    callback = function(info)
      input_mode_leave_callback(info.buf)
    end,
  })
end

return {
  setup = setup,
}
