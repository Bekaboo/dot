local utils = require('plugin.aider.utils')
local configs = require('plugin.aider.configs')
local term_t = require('utils.term_t')

local AIDER_CMD_REGEX = vim.regex(
  [[\v(sudo(\s+--?(\w|-)+((\s+|\=)\S+)?)*\s+)?(.*(sh\s+-c|python)\s+)?.*aider($|\s+)]]
)

---@class aider_chat_t : term_t
---@field watcher_timeout integer timeout waiting for aider to get ready for input and file change events after rendering
local aider_chat_t = setmetatable({ type = 'aider' }, { __index = term_t })

---@class aider_chat_opts_t
---@field dir? string path to project root directory where aider chat will be created
---@field buf? integer existing aider terminal buffer
---@field cmd? fun(path: string): string[] command to launch aider
---@field check_interval? integer timeout waiting for aider to render
---@field watcher_timeout? integer timeout waiting for aider to get ready for input and file change events after rendering
---@field win_configs? table

---Create a new aider chat
---@param opts? aider_chat_opts_t
---@return aider_chat_t?
function aider_chat_t:new(opts)
  opts = vim.tbl_deep_extend('force', configs.opts.chat, opts or {})

  local term_opts =
    vim.tbl_deep_extend('force', self, configs.opts.chat, opts or {}, {
      cmd = opts.cmd(opts.dir or vim.fn.getcwd(0)),
    })

  local chat = term_t:new(term_opts --[[@as term_opts_t]])
  if not chat then
    return
  end

  -- Convert to aider_chat_t
  ---@cast chat aider_chat_t
  setmetatable(chat, { __index = self })
  if not chat:validate() then
    return
  end

  -- Check file changed by aider on input or confirm pending
  chat:on_update(function()
    if chat:input_pending() or chat:confirm_pending() then
      chat:sync_files()
    end
  end)

  return chat
end

---Check if a chat is valid, delete it if not
---@return boolean
function aider_chat_t:validate()
  return term_t.validate(self)
    and utils.term.running(AIDER_CMD_REGEX, self.buf)
end

---Get a valid aider chat in `path`
---If `path` is not given, prefer current visible aider chat, if any
---@param path? string file or directory path, default to cwd
---@param tab? number default to current tabpage
---@return aider_chat_t? aider chat object at `path`
---@return boolean? is_new whether the chat is newly created or reused
function aider_chat_t:get(path, tab)
  ---@diagnostic disable-next-line: return-type-mismatch
  return term_t.get(self, configs.opts.root(path or vim.fn.getcwd(0)), tab)
end

---Open chat in current tabpage
---@param enter? boolean enter the chat window, default `true`
---@return integer? win window id of the opened terminal
function aider_chat_t:open(enter)
  local win = term_t.open(self, enter)
  if not win or win <= 0 then
    return
  end

  -- Aider hard-wraps lines itself, prevent content shift to left when
  -- cursor is at eol in chat window
  vim.wo[win][0].sidescrolloff = 0

  -- Good to set cwd to `dir` for better integration, e.g.
  -- we can use fuzzy finders like fzf-lua, telescope, etc. to find files
  -- in aider's dir (project root), or use `:e .` to edit project root
  vim.api.nvim_win_call(win, function()
    if vim.fn.getcwd(0) ~= self.dir then
      vim.cmd.lcd({
        vim.fn.fnameescape(self.dir),
        mods = { silent = true, emsg_silent = true },
      })
    end
  end)
end

---Send `lines` from `buf` to chat when aider is ready for input
---@param msg string|string[]
---@param buf integer? source of the message, default to current buffer
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

    -- Use term_t's send method through metatable
    term_t.send(self, msg)
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

return aider_chat_t
