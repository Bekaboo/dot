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
  -- We track *per-buffer* input method status in buffer-local variable
  -- `b:im_active`, this allows us to use IM in "input mode" in some buffers
  -- without affecting other buffers.
  --
  -- Since we can only toggle input method when we change mode or entering
  -- another buffer, we only update and read `b:im_active` under these three
  -- events:
  -- - ModeChanged
  -- - BufEnter
  -- - BufLeave
  --
  -- More specifically,
  --
  -- Maintenance of `b:im_active`: the flag is updated when:
  -- - Mode is changed from input mode to non-input mode. In this case, we save
  --   IM status in input mode before we toggle IM off in non-input mode so
  --   that we can restore IM status later when we re-enter input mode in the
  --   same buffer.
  -- - Leaving a buffer, but only when current mode is input mode. Saving
  --   IM status when mode is non-input mode is pointless because the IM status
  --   should always be off in this case.
  --
  -- Input method switching strategy: `b:im_active` is read and input method
  -- status is set when:
  -- - Mode is changed to input mode. In this case, we read saved `b:im_active`
  --   to check if IM was previously activated in input status and decide if we
  --   want to toggle IM back on.
  -- - Mode is changes to non-input mode. In this case, we turn off input
  --   method unconditionally.
  -- - Entering a buffer, and only when current mode is input mode. Reading
  --   `b:im_active` is useless if current mode is non-input mode as IM status
  --   should always be off.
  -- - Leaving a buffer. In this case, we turn off input method unconditionally.
  --   If the new buffer we are leaving for has input method on, input method
  --   will later be turned on by the BufEnter or ModeChanged event in the new
  --   buffer.
  --
  --
  -- (*) "Input modes" are modes where the input method should be activated,
  -- including insert mode, replace mode, terminal mode, select mode, and
  -- command mode when command type is '/', '?', '@', or '-'.
  -- Notice that command mode when command type is ':', '>', or '=' is not
  -- considered as input modes, because in these cases one will not want to
  -- insert CJK, even if the input method is activated in the current buffer.

  local utils = require('my.plugin.im.utils')

  local buf = vim.api.nvim_get_current_buf()
  if utils.inside_input_mode() then
    backend:try_turn_on(buf)
  end

  local groupid = vim.api.nvim_create_augroup('my.im', {})

  local prev_is_input_mode = utils.inside_input_mode()
  vim.api.nvim_create_autocmd('ModeChanged', {
    desc = 'Update `b:im_active` when switching from input mode to non-input mode.',
    group = groupid,
    callback = function(args)
      if prev_is_input_mode and not utils.inside_input_mode() then
        backend:save_status(args.buf)
      end
      prev_is_input_mode = utils.inside_input_mode()
    end,
  })

  vim.api.nvim_create_autocmd('BufLeave', {
    desc = 'Update `b:im_active` when switching away from current buffer.',
    group = groupid,
    callback = function(args)
      -- If current mode is input mode, save current IM status and deactivate
      -- IM. Don't save IM status if not currently in input mode as IM should
      -- always be off in this case.
      if utils.inside_input_mode() then
        backend:save_status(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd('ModeChanged', {
    desc = 'Disable input method after existing input mode.',
    group = groupid,
    callback = function()
      if not utils.inside_input_mode() then
        backend:turn_off()
      end
    end,
  })

  vim.api.nvim_create_autocmd('BufLeave', {
    desc = 'Disable input method after leaving current buf.',
    group = groupid,
    callback = function()
      backend:turn_off()
    end,
  })

  vim.api.nvim_create_autocmd({ 'ModeChanged', 'BufEnter' }, {
    desc = 'Restore input method status when entering input mode or a buffer.',
    group = groupid,
    callback = function(args)
      if utils.inside_input_mode() then
        backend:try_turn_on(args.buf)
      end
    end,
  })
end

return M
