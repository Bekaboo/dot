local utils = require('plugin.aider.utils')
local configs = require('plugin.aider.configs')

---@class aider_chat_t
---@field buf integer
---@field dir string
---@field chan integer channel associate with terminal buffer `buf`
---@field cmd string[] command to launch aider
---@field render_timeout integer timeout waiting for aider to render
---@field response_timeout integer timeout waiting for aider to generate response
---@field watcher_timeout integer timeout waiting for aider to get ready for input and file change events after rendering
---@field entered? boolean whether we have ever entered this aider terminal buffer
local aider_chat_t = {}

---@type table<string, aider_chat_t>
local chats = {}

---@class aider_chat_opts_t
---@field dir? string path to project root directory where aider chat will be created
---@field buf? integer existing aider terminal buffer
---@field cmd? string[] command to launch aider
---@field render_timeout? integer timeout waiting for aider to render
---@field response_timeout? integer timeout waiting for aider to generate response
---@field watcher_timeout? integer timeout waiting for aider to get ready for input and file change events after rendering

---Create a new aider chat
---@param opts? aider_chat_opts_t
---@return aider_chat_t?
function aider_chat_t.new(opts)
  opts = opts or {}

  local chat = (function()
    if opts.buf then
      return aider_chat_t._new_from_buf(opts)
    end
    return aider_chat_t._new_from_dir(opts)
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
---@param opts? aider_chat_opts_t
---@return aider_chat_t?
function aider_chat_t._new_from_buf(opts)
  if
    not opts
    or not opts.buf
    or not vim.api.nvim_buf_is_valid(opts.buf)
    or vim.bo[opts.buf].bt ~= 'terminal'
  then
    return
  end

  local dir, _, cmd =
    utils.term.parse_name(vim.api.nvim_buf_get_name(opts.buf))
  local aider_exe = configs.opts.chat.aider_cmd[1]
  if
    not vim.startswith(cmd, aider_exe)
    and not vim.startswith(cmd, vim.fn.exepath(aider_exe))
  then
    return
  end

  -- Create aider instance, no need to call `jobstart` as aider is already
  -- running in `buf`
  local chat = setmetatable({
    dir = dir,
    buf = opts.buf,
    chan = vim.b[opts.buf].terminal_job_id,
    cmd = opts.cmd or configs.opts.chat.aider_cmd,
    render_timeout = opts.render_timeout or configs.opts.chat.render_timeout,
    response_timeout = opts.response_timeout
      or configs.opts.chat.response_timeout,
    watcher_timeout = opts.watcher_timeout or configs.opts.chat.watcher_timeout,
  }, { __index = aider_chat_t })

  return chat
end

---@private
---@param opts? aider_chat_opts_t
---@return aider_chat_t?
function aider_chat_t._new_from_dir(opts)
  if not opts then
    opts = {}
  end

  if not opts.dir then
    opts.dir = vim.fn.getcwd(0)
  elseif vim.fn.isdirectory(opts.dir) == 0 then
    vim.notify(
      string.format("[aider] '%s' is not a valid directory", opts.dir),
      vim.log.levels.WARN
    )
    return
  end

  -- Create an aider instance
  local chat = setmetatable({
    dir = opts.dir,
    buf = vim.api.nvim_create_buf(false, true),
    cmd = opts.cmd or configs.opts.chat.aider_cmd,
    render_timeout = opts.render_timeout or configs.opts.chat.render_timeout,
    response_timeout = opts.response_timeout
      or configs.opts.chat.response_timeout,
    watcher_timeout = opts.watcher_timeout or configs.opts.chat.watcher_timeout,
  }, { __index = aider_chat_t })

  -- Launch aider CLI
  chat.chan = vim.api.nvim_buf_call(chat.buf, function()
    local aider_exe = chat.cmd[1]
    if not aider_exe or vim.fn.executable(aider_exe) == 0 then
      vim.notify_once(
        string.format('[aider] `%s` is not executable', tostring(aider_exe)),
        vim.log.levels.WARN
      )
      return 0
    end
    return vim.fn.jobstart(configs.opts.chat.aider_cmd, {
      term = true,
      cwd = opts.dir,
    })
  end)
  if chat.chan <= 0 then
    return -- failed to run `aider` command
  end

  return chat
end

---Stop and delete an aider chat
function aider_chat_t:del()
  -- Delete the temrinal buffer, this also closes the channel associated with
  -- the buffer
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    vim.api.nvim_buf_delete(self.buf, { force = true })
  end

  -- Remove from chat list
  if self.dir and (chats[self.dir] or {}).buf == self.buf then
    chats[self.dir] = nil
  end
end

---Check if a chat is valid, if not, delete the chat
---@return boolean
function aider_chat_t:validate()
  local valid = self.buf
    and self.chan
    and vim.api.nvim_buf_is_valid(self.buf)
    and not vim.tbl_isempty(vim.api.nvim_get_chan_info(self.chan))
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
    path = vim.fs.root(path, configs.opts.chat.root_markers)
      or vim.fs.dirname(path)
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
    if enter ~= false then
      vim.api.nvim_set_current_win(win)
    end
    return
  end

  -- Open a new window for the chat buffer in current tabpage
  local new_win = vim.api.nvim_open_win(
    self.buf,
    enter ~= false,
    vim.tbl_deep_extend(
      'force',
      configs.opts.chat.win_configs,
      win_configs or {}
    )
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

---Send `lines` from `buf` to chat when aider is ready for input
---@param msg string|string[]
---@param buf integer? source of the messag, default to current buffer
function aider_chat_t:send(msg, buf)
  self:wait_input_pending(function()
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
      buf = vim.api.nvim_get_current_buf()
    end
    if type(msg) ~= 'table' then
      msg = { msg }
    end
    -- Aider editor cannot render tabs correctly
    local tab_expanded = string.rep(' ', vim.bo[buf].tabstop)
    for i, line in ipairs(msg) do
      msg[i] = line:gsub('\t', tab_expanded)
    end
    utils.term.send(msg, self.buf)
  end)
end

---@param pattern string
---@return fun(chat: aider_chat_t): boolean
local function check_pending(pattern)
  return function(chat)
    if not chat:validate() then
      return false
    end

    local linenr = vim.api.nvim_buf_call(chat.buf, function()
      return vim.fn.prevnonblank(vim.api.nvim_buf_line_count(0))
    end)
    if linenr <= 0 then
      return false -- buffer is empty
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

---Check if chat is waiting for input, i.e. last line in aider buffer being
--- - ">"
--- - "multi>"
--- - "architect multi>"
aider_chat_t.input_pending = check_pending('>$')

---Wait to call `cb` until aider chat has pending input
---@param cb function
function aider_chat_t:wait_input_pending(cb)
  if not self:validate() then
    return
  end

  if self:input_pending() then
    cb()
    return
  end

  vim.defer_fn(function()
    self:wait_input_pending(cb)
  end, self.render_timeout)
end

---Wait a short time for aider to generate response
---@param cb function
function aider_chat_t:wait_response(cb)
  vim.defer_fn(cb, self.response_timeout)
end

---Wait a short time for aider's ai comment watcher to be ready after
---rendering the input prompt ">"
---@param cb function
function aider_chat_t:wait_watcher(cb)
  vim.defer_fn(cb, self.watcher_timeout)
end

---Reduce given path according to aider directory path
---@param path string
---@return string
function aider_chat_t:reduce_path(path)
  return vim.startswith(path, self.dir) and path:sub(#self.dir + 1) or path
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
