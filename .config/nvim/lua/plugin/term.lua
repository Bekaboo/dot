---Initial setup for a terminal buffer
---@param buf integer? terminal buffer handler
---@return nil
local function term_init(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].bt ~= 'terminal' then
    return
  end

  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    vim.wo[win][0].nu = false
    vim.wo[win][0].rnu = false
    vim.wo[win][0].spell = false
    vim.wo[win][0].statuscolumn = ''
    vim.wo[win][0].signcolumn = 'no'
  end
  vim.api.nvim_buf_call(buf, vim.cmd.startinsert)

  local term = require('utils.term')

  -- Create commands to rename terminals
  vim.api.nvim_buf_create_user_command(buf, 'TermRename', function(args)
    vim.cmd.file(
      vim.fn.fnameescape(
        term.compose_name(vim.api.nvim_buf_get_name(0), { name = args.args })
      )
    )
  end, {
    nargs = '?',
    desc = 'Rename current terminal',
    complete = function()
      local term_names = {}

      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[b].bt ~= 'terminal' then
          goto continue
        end
        local _, _, _, name = term.parse_name(vim.api.nvim_buf_get_name(b))
        if name == '' then
          goto continue
        end
        term_names[name] = true
        ::continue::
      end

      local compl = {}
      local _, _, _, curr_name = term.parse_name(vim.api.nvim_buf_get_name(0))
      for name, _ in pairs(term_names) do
        if name == curr_name then
          table.insert(compl, 1, name)
        else
          table.insert(compl, name)
        end
      end

      return compl
    end,
  })

  vim.api.nvim_buf_create_user_command(buf, 'TermSetCmd', function(args)
    local cmd = args.args
    if cmd == '' then
      cmd = vim.env.SHELL
    end

    vim.cmd.file(
      vim.fn.fnameescape(
        term.compose_name(vim.api.nvim_buf_get_name(0), { cmd = cmd })
      )
    )
  end, {
    nargs = '?',
    desc = 'Set cmd for current terminal',
    complete = 'shellcmdline',
  })

  vim.api.nvim_buf_create_user_command(buf, 'TermSetPath', function(args)
    local path = args.args
    if path == '' then
      path = vim.fn.getcwd(0)
    end

    vim.cmd.file(
      vim.fn.fnameescape(
        term.compose_name(vim.api.nvim_buf_get_name(0), { path = path })
      )
    )
  end, {
    nargs = '?',
    desc = 'Set path for current terminal',
    complete = 'dir',
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
end

return { setup = setup }
