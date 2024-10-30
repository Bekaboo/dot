---Set local terminal keymaps and options, start insert immediately
---@param buf integer terminal buffer handler
---@return nil
local function term_set_local_keymaps_and_opts(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].bt ~= 'terminal' then
    return
  end

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
end

---@param buf integer terminal buffer handler
---@return nil
local function setup(buf)
  term_set_local_keymaps_and_opts(buf)

  local groupid = vim.api.nvim_create_augroup('Term', {})
  vim.api.nvim_create_autocmd('TermOpen', {
    group = groupid,
    desc = 'Set terminal keymaps and options, open term in split.',
    callback = function(info)
      term_set_local_keymaps_and_opts(info.buf)
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
