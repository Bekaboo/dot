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

  -- Start with insert mode in new terminals
  -- Use `vim.schedule()` to avoid ending with insert mode in a normal buffer
  -- after loading a session with terminal buffers
  vim.schedule(function()
    if vim.api.nvim_get_current_buf() == buf then
      vim.cmd.startinsert()
    end
  end)

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
end

return { setup = setup }
