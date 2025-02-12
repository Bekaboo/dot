---Initial setup for a terminal buffer
---@param buf integer? terminal buffer handler
---@return nil
local function term_init(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].bt ~= 'terminal' then
    return
  end

  vim.api.nvim_buf_call(buf, function()
    vim.opt_local.nu = false
    vim.opt_local.rnu = false
    vim.opt_local.spell = false
    vim.opt_local.statuscolumn = ''
    vim.opt_local.signcolumn = 'no'
    if vim.fn.win_gettype() == 'popup' then
      vim.opt_local.scrolloff = 0
      vim.opt_local.sidescrolloff = 0
    end
    vim.cmd.startinsert()
  end)

  -- Rename terminal in a way that can be recovered from a session file
  vim.api.nvim_buf_create_user_command(buf, 'TermRename', function(args)
    vim.cmd.file(
      string.format(
        '%s%s',
        vim.api.nvim_buf_get_name(0):gsub('%s*#%s.*', ''),
        args.args == '' and '' or ' \\# ' .. vim.fn.fnameescape(args.args)
      )
    )
  end, {
    nargs = '?',
    desc = 'Rename current terminal',
  })
end

---Plugin initialize function
---@return nil
local function setup()
  if vim.g.loaded_term_plugin ~= nil then
    return
  end
  vim.g.loaded_term_plugin = true

  -- Wisely exit terminal mode with <Esc>
  vim.keymap.set(
    't',
    '<Esc>',
    [[v:lua.require'utils.term'.running_tui() ? "<Esc>" : "<Cmd>stopi<CR>"]],
    { expr = true, replace_keycodes = false, desc = 'Exit terminal mode' }
  )

  -- Use <C-\><C-r> to insert contents of a register in terminal mode
  vim.keymap.set(
    't',
    [[<C-\><C-r>]],
    [['<C-\><C-n>"' . nr2char(getchar()) . 'pi']],
    { expr = true, desc = 'Insert contents in a register' }
  )

  vim
    .iter(vim.api.nvim_list_bufs())
    :filter(function(buf)
      return vim.bo[buf].bt == 'terminal'
    end)
    :each(function(buf)
      term_init(buf)
    end)

  local groupid = vim.api.nvim_create_augroup('Term', {})
  vim.api.nvim_create_autocmd('TermOpen', {
    group = groupid,
    desc = 'Set terminal keymaps and options, open term in split.',
    callback = function(info)
      term_init(info.buf)
    end,
  })

  vim.api.nvim_create_autocmd('TermEnter', {
    group = groupid,
    desc = 'Disable mousemoveevent in terminal mode.',
    callback = function()
      vim.g.mousemev = vim.go.mousemev
      vim.go.mousemev = false
    end,
  })

  vim.api.nvim_create_autocmd('TermLeave', {
    group = groupid,
    desc = 'Restore mousemoveevent after leaving terminal mode.',
    callback = function()
      if vim.g.mousemev ~= nil then
        vim.go.mousemev = vim.g.mousemev
        vim.g.mousemev = nil
      end
    end,
  })

  vim.api.nvim_create_autocmd('ModeChanged', {
    group = groupid,
    desc = 'Record mode in terminal buffer.',
    callback = function(info)
      if vim.bo[info.buf].bt == 'terminal' then
        vim.b[info.buf].termode = vim.api.nvim_get_mode().mode
      end
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter' }, {
    group = groupid,
    desc = 'Recover inseart mode when entering terminal buffer.',
    callback = function(info)
      if
        vim.bo[info.buf].bt == 'terminal'
        and vim.b[info.buf].termode == 't'
      then
        vim.cmd.startinsert()
      end
    end,
  })
end

return { setup = setup }
