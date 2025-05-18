local utils = require('plugin.aider.utils')
local configs = require('plugin.aider.configs')

local aider_cmd_regex = vim.regex(
  [[\v(sudo(\s+--?(\w|-)+((\s+|\=)\S+)?)*\s+)?(.*(sh\s+-c|python)\s+)?.*aider($|\s\+)]]
)

---Check whether a terminal buffer is running aider
---@param buf? integer
---@return boolean
local function running_aider(buf)
  return utils.term.running(aider_cmd_regex, buf)
end

---@class aider_chat_t
---@field buf integer
---@field dir string
---@field chan integer channel associate with terminal buffer `buf`
---@field cmd string[] command to launch aider
---@field check_interval integer timeout waiting for aider to render
---@field watcher_timeout integer timeout waiting for aider to get ready for input and file change events after rendering
---@field entered? boolean whether we have ever entered this aider terminal buffer
---@field win_configs vim.api.keyset.win_config
local aider_chat_t = {}

---@type table<string, aider_chat_t>
local chats = {}

---@class aider_chat_opts_t
---@field dir? string path to project root directory where aider chat will be created
---@field buf? integer existing aider terminal buffer
---@field cmd? fun(path: string): string[] command to launch aider
---@field check_interval? integer timeout waiting for aider to render
---@field watcher_timeout? integer timeout waiting for aider to get ready for input and file change events after rendering
---@field win_configs? vim.api.keyset.win_config

---Create a new aider chat
---@param opts? aider_chat_opts_t
---@return aider_chat_t?
function aider_chat_t.new(opts)
  opts = vim.tbl_deep_extend('force', configs.opts.chat, opts or {})

  local chat = (function()
    if opts.buf then
      return aider_chat_t._new_from_buf(opts)
    end
    return aider_chat_t._new_from_dir(opts)
  end)()

  if not chat then
    return
  end

  -- Check file changed by aider on input or confirm pending
  chat:on_update(function()
    if chat:input_pending() or chat:confirm_pending() then
      chat:sync_files()
    end
  end)

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

  if not running_aider(opts.buf) then
    return
  end

  -- Create aider instance, no need to call `jobstart` as aider is already
  -- running in `buf`
  local chat = setmetatable(
    vim.tbl_deep_extend('force', configs.opts.chat, opts, {
      dir = utils.term.parse_name(vim.api.nvim_buf_get_name(opts.buf)),
      chan = vim.b[opts.buf].terminal_job_id,
    }),
    { __index = aider_chat_t }
  )

  return chat --[[@as aider_chat_t]]
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
  local chat = setmetatable(
    vim.tbl_deep_extend('force', configs.opts.chat, opts, {
      buf = vim.api.nvim_create_buf(false, true),
    }),
    { __index = aider_chat_t }
  )

  -- Launch aider CLI
  chat.chan = vim.api.nvim_buf_call(chat.buf, function()
    local aider_cmd = chat.cmd(opts.dir)
    local aider_exe = aider_cmd[1]
    if not aider_exe or vim.fn.executable(aider_exe) == 0 then
      vim.notify_once(
        string.format('[aider] `%s` is not executable', tostring(aider_exe)),
        vim.log.levels.WARN
      )
      return 0
    end
    return vim.fn.jobstart(aider_cmd, {
      term = true,
      cwd = opts.dir,
    })
  end)
  if chat.chan <= 0 then
    return -- failed to run `aider` command
  end

  return chat --[[@as aider_chat_t]]
end

---Stop and delete an aider chat
function aider_chat_t:del()
  -- Delete the terminal buffer, this also closes the channel associated with
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
---If `path` is not given, prefer current visible aider chat, if any
---@param path? string file or directory path, default to cwd
---@param tab? number default to current tabpage
---@return aider_chat_t? aider chat object at `path`
---@return boolean? is_new whether the chat is newly created or reused
function aider_chat_t.get(path, tab)
  if not path then
    path = vim.fn.getcwd(0)
    -- Check if there is any aider chat visible in given tabpage
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab or 0)) do
      local buf = vim.fn.winbufnr(win)
      if vim.bo[buf].ft == 'aider' then
        path = utils.term.parse_name(vim.api.nvim_buf_get_name(buf))
        break
      end
    end
  else
    local stat = vim.uv.fs_stat(path)
    if not stat then
      return
    end
    if stat.type ~= 'directory' then
      path = vim.fs.dirname(path)
    end
  end
  -- Normalized `path`, always use absoluate path and include trailing slash
  path = vim.fn.fnamemodify(configs.opts.root(path) or path, ':p')

  local chat = chats[path]
  if chat and chat:validate() then
    return chat, false
  end

  -- Aider chat not exist in `chats` table, add existing manually created chat
  -- buffer (via `:terminal aider ...`) as chat or create new chat buffer
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if running_aider(buf) then
      return aider_chat_t.new({ buf = buf }), true
    end
  end
  return aider_chat_t.new({ dir = path }), true
end

---Open chat in current tabpage
---@param enter? boolean enter the chat window, default `true`
function aider_chat_t:open(enter)
  if not self:validate() then
    return
  end

  enter = enter ~= false
  -- Chat already visible in current tabpage, switch to it
  local win = self:wins():next()
  if win then
    if enter then
      vim.api.nvim_set_current_win(win)
    end
    return
  end

  -- Open a new window for the chat buffer in current tabpage
  local new_win = vim.api.nvim_open_win(self.buf, enter, self.win_configs)
  if new_win > 0 and not self.entered then
    -- Aider hard-wraps lines itself, prevent content shift to left when
    -- cursor is at eol in chat window
    vim.wo[new_win][0].sidescrolloff = 0

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
  self:on_update(function()
    if not self:input_pending() then
      return
    end

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
    return true -- send once only
  end)
end

---Get line number of last non-blank line
---@return integer 1-based line number, 0 if lnum is invalid or there is no non-blank line at or above it
function aider_chat_t:last_nonblank_lnum()
  if not self:validate() then
    return 0
  end

  return vim.api.nvim_buf_call(self.buf, function()
    return vim.fn.prevnonblank(vim.api.nvim_buf_line_count(0))
  end)
end

---Check if the last non-blank line in chat buffer matches `pattern`
---@param pattern string
---@return boolean
function aider_chat_t:last_line_matches(pattern)
  if not self:validate() then
    return false
  end

  local linenr = self:last_nonblank_lnum()
  if linenr <= 0 then
    return false -- buffer is empty
  end

  return vim.api
    .nvim_buf_get_lines(self.buf, linenr - 1, linenr, false)[1]
    :match(pattern) ~= nil
end

---Check if chat has pending confirm, e.g.
--- - "Add file to the chat? (Y)es/(N)o/(D)on't ask again \[Yes\]:"
--- - "No git repo found, create one to track aider's changes (recommended)? (Y)es/(N)o \[Yes\]:"
---@return boolean
function aider_chat_t:confirm_pending()
  return self:last_line_matches('? %(Y%)es/%(N%)o.*%[.+%]:')
end

---Check if chat is waiting for input, i.e. last line in aider buffer being
--- - ">"
--- - "multi>"
--- - "architect multi>"
---@return boolean
function aider_chat_t:input_pending()
  return self:last_line_matches('>$')
end

---Call `cb` on aider buffer update
---@param cb fun(chat: aider_chat_t): any
---@param tick? integer previous update's `b:changedtick`, should be `nil` on first call
function aider_chat_t:on_update(cb, tick)
  if not self:validate() then
    return
  end

  local cur_tick = vim.b[self.buf].changedtick

  -- Cancel following calls if callback returns a truethy value
  if cur_tick ~= tick and cb(self) then
    return
  end

  -- Schedule for next update
  vim.defer_fn(function()
    self:on_update(cb, cur_tick)
  end, self.check_interval)
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

---Synchronize buffers with files being edited by aider
---@param file? string file to sync (defaults to all files)
function aider_chat_t:sync_files(file)
  vim.schedule(function()
    vim.cmd.checktime({
      file and vim.fn.fnameescape(vim.fs.normalize(file)),
      mods = { emsg_silent = true },
    })
    -- HACK: don't know why but aider's syntax will be set to the
    -- source buffer's syntax after time check, set it back to
    -- empty to disable wrong syntax highlighting in aider buffers
    vim.schedule(function()
      if self:validate() then
        vim.bo[self.buf].syntax = ''
      end
    end)
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
