local utils = require('plugin.aider.utils')
local configs = require('plugin.aider.configs')

---@class aider_chat_t
---@field buf integer
---@field path string
---@field entered? true whether we have ever entered this aider terminal buffer
local aider_chat_t = {}

---@type table<string, aider_chat_t>
local chats = {}

---@class aider_chat_opts_t
---@field path? string path to a project or a project file, aider chat will be created at the project root
---@field buf? integer existing aider terminal buffer

---Create a new aider chat
---@param opts? aider_chat_opts_t
---@return aider_chat_t?
function aider_chat_t.new(opts)
  opts = opts or {}

  local chat = (function()
    if opts.buf then
      return aider_chat_t._new_from_buf(opts.buf)
    end
    return aider_chat_t._new_from_path(opts.path)
  end)()

  if not chat then
    return
  end

  -- Indicate aider terminal buffer
  vim.bo[chat.buf].ft = 'aider'

  -- Record chat to chats indexed by cwd
  local old_chat = chats[chat.path]
  if old_chat and vim.api.nvim_buf_is_valid(old_chat.buf) then
    vim.api.nvim_buf_delete(old_chat.buf, { force = true })
  end
  chats[chat.path] = chat

  return chat
end

---Create aider from existing aider terminal buffer
---@private
---@param buf? integer
---@return aider_chat_t?
function aider_chat_t._new_from_buf(buf)
  if
    not buf
    or not vim.api.nvim_buf_is_valid(buf)
    or vim.bo[buf].bt ~= 'terminal'
  then
    return
  end

  local path, _, cmd = utils.term.parse_name(vim.api.nvim_buf_get_name(buf))
  local aider_exe = configs.opts.aider_cmd[1]
  if
    not vim.startswith(cmd, aider_exe)
    and not vim.startswith(cmd, vim.fn.exepath(aider_exe))
  then
    return
  end

  -- Create aider instance, no need to call `jobstart` as aider is already
  -- running in `buf`
  local chat = setmetatable({ path = path, buf = buf }, {
    __index = aider_chat_t,
  })

  return chat
end

---@private
---@param path? string
---@return aider_chat_t?
function aider_chat_t._new_from_path(path)
  if not path then
    path = vim.fn.getcwd(0)
  elseif vim.fn.isdirectory(path) == 0 then
    vim.notify(
      string.format("[aider] '%s' is not a valid directory", path),
      vim.log.levels.WARN
    )
    return
  end

  -- Create an aider instance
  local chat = setmetatable(
    { path = path, buf = vim.api.nvim_create_buf(false, true) },
    { __index = aider_chat_t }
  )
  if
    vim.api.nvim_buf_call(chat.buf, function()
      return vim.fn.jobstart(configs.opts.aider_cmd, {
        term = true,
        cwd = path,
      })
    end) < 0
  then
    return -- failed to run `aider` command
  end

  return chat
end

---Stop and delete an aider chat
---TODO
function aider_chat_t:del()
  if not self.buf then
    return
  end

  -- Delete buffer
  if vim.api.nvim_buf_is_valid(self.buf) then
    vim.api.nvim_buf_delete(self.buf, { force = true })
  end

  -- Remove from chat list
  if self.path then
    chats[self.path] = nil
  end
end

---Get a valid aider chat in `path`
---@param path? string default to cwd
---@return aider_chat_t?
function aider_chat_t.get(path)
  if not path then
    path = vim.fn.fnamemodify(vim.fn.getcwd(0), ':p')
  end
  local chat = chats[path]
  if chat and vim.api.nvim_buf_is_valid(chat.buf) then
    return chat
  end
  return aider_chat_t.new({ path = path })
end

---Open chat in current tabpage
---@param win_configs? vim.api.keyset.win_config
function aider_chat_t:open(win_configs)
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
    return
  end

  -- Chat already visible in current tabpage, switch to it
  local win = self:visible():next()
  if win then
    vim.api.nvim_set_current_win(win)
    return
  end

  -- Open a new window for the chat buffer in current tabpage
  local new_win = vim.api.nvim_open_win(
    self.buf,
    true,
    vim.tbl_deep_extend('force', configs.opts.win_configs, win_configs or {})
  )
  if new_win > 0 and not self.entered then
    vim.api.nvim_win_call(new_win, function()
      -- Good to set cwd to `path` for better integration, e.g.
      -- we can use fuzzy finders like fzf-lua, telescope, etc. to find files
      -- in aider's path (project root), or use `:e .` to edit project root
      if vim.fn.getcwd(0) ~= self.path then
        vim.cmd.lcd({
          vim.fn.fnameescape(self.path),
          mods = { silent = true, emsg_silent = true },
        })
      end
      -- Default terminal settings does not apply if terminal is launched using
      -- `jobstart()` and opened using `nvim_open_win()`, so manually trigger
      -- `TermOpen` event on the first time entering the aider chat terminal buffer
      -- to apply them
      -- See `:h default-autocmds` and `lua/plugin/term.lua`
      vim.api.nvim_exec_autocmds('TermOpen', { buffer = self.buf })
    end)
    self.entered = true
  end
end

---Close aider chat window in current tabpage
function aider_chat_t:close()
  for win in self:visible() do
    -- Don't close the only window in current tabpage
    if #vim.api.nvim_tabpage_list_wins(0) <= 1 then
      vim.api.nvim_set_current_buf(vim.fn.bufnr('#'))
      break
    end
    vim.api.nvim_win_close(win, true)
  end
end

---Toggle aider chat
function aider_chat_t:toggle()
  if self:visible():peek() then
    self:close()
  else
    self:open()
  end
end

---@param tabpage? integer tabpage id, default to current tabpage
---@return Iter wins iterator of windows containing chat if it is visible in given tabpage, else `nil`
function aider_chat_t:visible(tabpage)
  if not vim.api.nvim_buf_is_valid(self.buf) then
    return vim.iter({})
  end

  if not tabpage then
    tabpage = vim.api.nvim_get_current_tabpage()
  elseif not vim.api.nvim_tabpage_is_valid(tabpage) then
    return vim.iter({})
  end

  return vim.iter(vim.api.nvim_tabpage_list_wins(tabpage)):filter(function(win)
    return vim.fn.winbufnr(win) == self.buf
  end)
end

---Iterate all buffers and add aider terminal buffers to `chats`
local function init_chats()
  if not vim.tbl_isempty(chats) then
    return
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    aider_chat_t.new({ buf = buf })
  end
end

-- Chat terminals can be restored from session files without adding to the chat
-- list, so check all the buffers once and create aider instances for aider
-- terminal buffers
init_chats()
vim.api.nvim_create_autocmd('SessionLoadPost', {
  once = true,
  callback = init_chats,
})

return aider_chat_t
