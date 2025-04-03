local utils = require('plugin.aider.utils')
local configs = require('plugin.aider.configs')

---@class aider_chat_t
---@field buf integer
---@field dir string
---@field entered? true whether we have ever entered this aider terminal buffer
local aider_chat_t = {}

---@type table<string, aider_chat_t>
local chats = {}

---@class aider_chat_opts_t
---@field dir? string path to project root directory where aider chat will be created
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
    return aider_chat_t._new_from_dir(opts.dir)
  end)()

  if not chat then
    return
  end

  -- Indicate aider terminal buffer
  vim.bo[chat.buf].ft = 'aider'

  -- Record chat to chats indexed by cwd
  local old_chat = chats[chat.dir]
  if old_chat then
    old_chat:del()
  end
  chats[chat.dir] = chat

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

  local dir, _, cmd = utils.term.parse_name(vim.api.nvim_buf_get_name(buf))
  local aider_exe = configs.opts.chat.aider_cmd[1]
  if
    not vim.startswith(cmd, aider_exe)
    and not vim.startswith(cmd, vim.fn.exepath(aider_exe))
  then
    return
  end

  -- Create aider instance, no need to call `jobstart` as aider is already
  -- running in `buf`
  local chat = setmetatable({ dir = dir, buf = buf }, {
    __index = aider_chat_t,
  })

  return chat
end

---@private
---@param dir? string
---@return aider_chat_t?
function aider_chat_t._new_from_dir(dir)
  if not dir then
    dir = vim.fn.getcwd(0)
  elseif vim.fn.isdirectory(dir) == 0 then
    vim.notify(
      string.format("[aider] '%s' is not a valid directory", dir),
      vim.log.levels.WARN
    )
    return
  end

  -- Create an aider instance
  local chat = setmetatable(
    { dir = dir, buf = vim.api.nvim_create_buf(false, true) },
    { __index = aider_chat_t }
  )
  if
    vim.api.nvim_buf_call(chat.buf, function()
      if not configs.validate(configs.opts) then
        return 0
      end
      return vim.fn.jobstart(configs.opts.chat.aider_cmd, {
        term = true,
        cwd = dir,
      })
    end) <= 0
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
  if self.dir then
    chats[self.dir] = nil
  end
end

---Check if a chat is valid, if not, delete the chat
---@return boolean
function aider_chat_t:validate()
  local valid = self.buf and vim.api.nvim_buf_is_valid(self.buf)
  if not valid then
    self:del()
  end
  return valid
end

---Get a valid aider chat in `path`
---@param path? string file or directory path, default to cwd
---@return aider_chat_t?
function aider_chat_t.get(path)
  if not path then
    path = vim.fn.getcwd(0)
  end
  if vim.fn.isdirectory(path) == 0 then
    path = vim.fs.root(path, configs.opts.chat.root_markers) or vim.fs.dirname(path)
  end
  if not vim.uv.fs_stat(path) then
    return
  end
  -- Normalized `path`, always use absoluate path and include trailing slash
  path = vim.fn.fnamemodify(path, ':p')

  local chat = chats[path]
  if chat and chat:validate() then
    return chat
  end
  return aider_chat_t.new({ dir = path })
end

---Open chat in current tabpage
---@param win_configs? vim.api.keyset.win_config
---@param enter? boolean enter the chat window, default `true`
function aider_chat_t:open(win_configs, enter)
  if not self:validate() then
    return
  end

  -- Chat already visible in current tabpage, switch to it
  local win = self:wins():next()
  if win then
    if enter or enter == nil then
      vim.api.nvim_set_current_win(win)
    end
    return
  end

  -- Open a new window for the chat buffer in current tabpage
  local new_win = vim.api.nvim_open_win(
    self.buf,
    true,
    vim.tbl_deep_extend('force', configs.opts.chat.win_configs, win_configs or {})
  )
  if new_win > 0 and not self.entered then
    vim.api.nvim_win_call(new_win, function()
      -- Good to set cwd to `dir` for better integration, e.g.
      -- we can use fuzzy finders like fzf-lua, telescope, etc. to find files
      -- in aider's dir (project root), or use `:e .` to edit project root
      if vim.fn.getcwd(0) ~= self.dir then
        vim.cmd.lcd({
          vim.fn.fnameescape(self.dir),
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
  for win in self:wins() do
    -- Don't close the only window in current tabpage
    -- Try switching to alternative buffer to "close" the chat
    if #vim.api.nvim_tabpage_list_wins(0) <= 1 then
      local alt_buf = vim.fn.bufnr('#')
      if alt_buf > 0 and alt_buf ~= self.buf then
        vim.api.nvim_set_current_buf(alt_buf)
      end
      break
    end
    vim.api.nvim_win_close(win, true)
  end
end

---Toggle aider chat
function aider_chat_t:toggle()
  if self:wins():peek() then
    self:close()
  else
    self:open()
  end
end

---Get windows containing aider buffer in given `tabpage`
---@param tabpage? integer tabpage id, default to current tabpage
---@return Iter wins iterator of windows containing chat if it is visible in given tabpage, else `nil`
function aider_chat_t:wins(tabpage)
  if not self:validate() then
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

---@param pattern string
---@return fun(chat: aider_chat_t): boolean
local function check_pending(pattern)
  return function(chat)
    if not chat:validate() then
      return false
    end

    local linenr = vim.fn.prevnonblank(vim.api.nvim_buf_line_count(chat.buf))
    if linenr <= 0 then
      return true
    end

    return vim.api
      .nvim_buf_get_lines(chat.buf, linenr - 1, linenr, false)[1]
      :match(pattern) ~= nil
  end
end

---Check if chat has pending confirm, e.g.
--- - "Add file to the chat? (Y)es/(N)o/(D)on't ask again \[Yes\]:"
--- - "No git repo found, create one to track aider's changes (recommended)? (Y)es/(N)o \[Yes\]:"
aider_chat_t.confirm_pending = check_pending('%(Y%)es/*%(N%)o')

---Check if chat is waiting for input, e.g.
--- - ">"
--- - "multi>"
--- - "architect multi>"
aider_chat_t.input_pending = check_pending('>$')

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
