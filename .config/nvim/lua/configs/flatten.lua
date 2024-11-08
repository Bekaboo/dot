---Check if a file is a git (commit, rebase, etc.) file
---@param fpath string
---@return boolean
local function should_block_file(fpath)
  fpath = vim.fn.fnamemodify(fpath, ':p')
  return fpath:match('COMMIT_EDITMSG$')
    or fpath:match('/rebase%-merge/')
    or fpath:match('^/tmp/.*%.fish')
end

if tonumber(vim.fn.system({ 'id', '-u' })) == 0 then
  vim.env['NVIM_ROOT_' .. vim.fn.getpid()] = '1'
end

require('flatten').setup({
  window = {
    open = 'current',
  },
  callbacks = {
    -- Nest when child nvim is root but parent nvim (current session) is not
    -- to avoid opening files in current session without write permission
    should_nest = function()
      local pid = vim.fn.getpid()
      local parent_pid = vim.env.NVIM and vim.env.NVIM:match('nvim%.(%d+)')
      if
        vim.env['NVIM_ROOT_' .. pid]
        and parent_pid
        and not vim.env['NVIM_ROOT_' .. parent_pid]
      then
        return true
      end
    end,
    should_block = function()
      local files = vim.fn.argv() --[=[@as string[]]=]
      for _, file in ipairs(files) do
        if should_block_file(file) then
          return true
        end
      end
      return false
    end,
    post_open = function(buf, win)
      vim.api.nvim_set_current_win(win)
      local bufname = vim.api.nvim_buf_get_name(buf)
      if should_block_file(bufname) then
        vim.bo[buf].bufhidden = 'wipe'
        local keymap_utils = require('utils.keymap')
        -- stylua: ignore start
        keymap_utils.command_abbrev('x',  'b#', { buffer = buf })
        keymap_utils.command_abbrev('wq', 'b#', { buffer = buf })
        keymap_utils.command_abbrev('bw', 'b#', { buffer = buf })
        keymap_utils.command_abbrev('bd', 'b#', { buffer = buf })
        -- stylua: ignore end
      end
    end,
  },
  one_per = {
    kitty = false,
    wezterm = false,
  },
})
