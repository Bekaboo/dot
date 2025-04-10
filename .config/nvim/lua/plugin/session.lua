local M = {}

---Check if a buffer is "valid"
---@param buf integer
---@return boolean
local function buf_valid(buf)
  if vim.fn.buflisted(buf) == 0 and vim.fn.bufwinid(buf) == -1 then
    return false
  end

  local bt = vim.bo[buf].bt
  if
    bt == 'help'
    or bt == 'quickfix'
    or bt == 'terminal'
    or bt == 'prompt'
  then
    return false
  end

  local ft = vim.bo[buf].ft
  if ft == 'gitcommit' or ft == 'gitrebase' then
    return false
  end

  local bufname = vim.api.nvim_buf_get_name(buf)
  if bufname == '' or vim.startswith(bufname, '/tmp/') then
    return false
  end

  return true
end

---Check if nvim has any "valid" buf
---@return boolean
local function has_valid_buf()
  return vim.iter(vim.api.nvim_list_bufs()):any(buf_valid)
end

---@class session_opts_t
M.opts = {
  dir = vim.fs.joinpath(vim.fn.stdpath('data') --[[@as string]], 'session'),
  ---Given path, return project root, used to determine the name of the session
  ---file to be autosaved
  ---@param path string
  ---@return string?
  root = function(path)
    return vim.fs.root(path, require('utils.fs').root_markers)
      or vim.fn.isdirectory(path) == 1 and path
      or vim.fs.dirname(path)
  end,
  autoload = {
    enabled = true,
    events = { 'UIEnter' },
  },
  autosave = {
    enabled = true,
    events = {
      'BufNew',
      'BufNewFile',
      'BufDelete',
      'TermOpen',
      'TermClose',
      'WinNew',
      'WinClosed',
      'DirChanged',
      'FileChangedShellPost',
      'VimLeave',
    },
    ---Condition to automatically save sessions
    ---@type fun(): boolean
    cond = has_valid_buf,
  },
  autoremove = {
    enabled = true,
    events = { 'BufDelete' },
    ---@type fun(): boolean
    cond = has_valid_buf,
  },
}

---Convert session name to corresponding dir, e.g.
---'foo%bar%baz' -> 'foo/bar/baz/'
---@param session_name string
---@return string dir
function M.session2dir(session_name)
  return (session_name:gsub('%%', '/'):gsub('//', '%'))
end

---Convert directory to corresponding session name, e.g.
---'foo/bar/baz/' -> 'foo%bar%baz'
---@param dir string
---@return string session_name
function M.dir2session(dir)
  return (vim.fs.normalize(dir):gsub('%%', '%%%%'):gsub('/', '%%'))
end

---Get session file path for given path
---@param path? string default to cwd
---@return string
function M.get(path)
  if not path then
    path = vim.fn.getcwd(0)
  else
    local stat = vim.uv.fs_stat(path)
    if not stat then
      return ''
    end
    if stat.type ~= 'directory' then
      path = vim.fs.dirname(path)
    end
  end
  path = M.opts.root(path) or path

  local session_dir = M.opts.dir
  if vim.fn.isdirectory(session_dir) == 0 then
    vim.fn.mkdir(session_dir, 'p')
  end

  return vim.fs.joinpath(
    session_dir,
    M.dir2session(vim.fn.fnamemodify(path, ':p'))
  )
end

---Save current session
---@param session? string path to session file to save to
function M.save(session)
  if not session then
    session = M.get()
  end

  vim.cmd.mksession({
    vim.fn.fnameescape(session),
    bang = true,
    mods = {
      silent = true,
      emsg_silent = true,
    },
  })
end

---Remove given session file
---@param session? string path to session file to remove, default to previously loaded session file
function M.remove(session)
  session = session or vim.g._session_loaded
  if session then
    vim.fn.delete(session)
  end
end

---Load current session
---@param session? string path to session file to load from
function M.load(session)
  if not session then
    session = M.get()
  end
  if not vim.uv.fs_stat(session) then
    vim.notify(
      string.format("[session] session '%s' does not exist", session),
      vim.log.levels.WARN
    )
    return
  end

  vim.g._session_loaded = session

  -- Avoid intro message flickering before loading session,
  -- see `plugin/intro.lua` and `:h :intro`
  vim.opt.shortmess:append('I')
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.fn.win_id2win(win) ~= 1 then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.schedule(function()
    vim.cmd.source({
      vim.fn.fnameescape(session),
      mods = {
        silent = true,
        emsg_silent = true,
      },
    })
  end)
end

---List all session files
---@return string[]
function M.list()
  return vim
    .iter(vim.fs.dir(M.opts.dir))
    :filter(function(_, type)
      return type == 'file'
    end)
    :map(function(session)
      return vim.fs.joinpath(M.opts.dir, session)
    end)
    :totable()
end

---Wrapper to call `cb` without triggering autoload/save/remove events, useful
---for avoiding loading/changing/removing session files in `vim.ui.select()`
---or some other fuzzy-find tools
---@param cb fun(finish: function): any?
function M.no_auto(cb)
  local eventignore = vim.go.eventignore
  for _, auto in ipairs({ 'autoload', 'autosave', 'autoremove' }) do
    for _, event in ipairs(M.opts[auto].events) do
      vim.opt.eventignore:append(event)
    end
  end

  cb(function()
    vim.go.eventignore = eventignore
  end)
end

---Interactively select and load a session file using `vim.ui.select()`
function M.select()
  M.no_auto(function(finish)
    vim.ui.select(M.list(), {
      prompt = 'Load session: ',
      format_item = function(session)
        return M.session2dir(vim.fn.fnamemodify(session, ':t'))
      end,
    }, function(choice)
      if choice then
        M.load(choice)
      end
      finish()
    end)
  end)
end

---Session completion function
---@param arglead string
---@return string[] list of session names
local function cmp(arglead)
  return vim
    .iter(M.list())
    :map(function(session)
      return M.session2dir(vim.fn.fnamemodify(session, ':t'))
    end)
    :filter(function(dir)
      return string.find(dir, arglead, nil, true) ~= nil
    end)
    :totable()
end

---Session command function
---@param cb fun(path?: string)
---@return function
local function cmd(cb)
  return function(args)
    cb(
      args.args ~= '' and vim.fs.joinpath(M.opts.dir, M.dir2session(args.args))
        or nil
    )
  end
end

---@param opts? table
---@return boolean?
local function check_enabled(opts)
  return opts and opts.enabled and not vim.tbl_isempty(opts.events)
end

---@param opts? session_opts_t
function M.setup(opts)
  M.opts = vim.tbl_deep_extend('force', M.opts, opts or {})
  M.opts.dir = vim.fn.fnamemodify(M.opts.dir, ':p')

  if vim.g.loaded_session ~= nil then
    return
  end
  vim.g.loaded_session = true

  -- Setup autocmds for autosave/remove/load
  if check_enabled(M.opts.autosave) then
    -- Wait for buffer options & names to be set before checking for named buffers
    -- and saving the session
    vim.schedule(function()
      if M.opts.autosave.cond() then
        M.save()
      end
    end)

    vim.api.nvim_create_autocmd(M.opts.autosave.events, {
      group = vim.api.nvim_create_augroup('SessionAutoSave', {}),
      desc = 'Automatically save session.',
      -- `BufDelete` event triggers just before the buffers is actually deleted from
      -- the buffer list, delay to ensure that the buffer is deleted before checking
      -- for named buffers
      callback = vim.schedule_wrap(function()
        if M.opts.autosave.cond() then
          M.save()
        end
      end),
    })
  end

  if check_enabled(M.opts.autoload) then
    local groupid = vim.api.nvim_create_augroup('SessionAutoLoad', {})
    vim.api.nvim_create_autocmd({ 'StdinReadPre', 'SessionLoadPost' }, {
      desc = 'Detect stdin or manual session loading to disable automatic session loading.',
      group = groupid,
      once = true,
      callback = function()
        vim.g._session_disabled = true
        return true
      end,
    })

    -- Don't load session if there is no argument, piping from stdin,
    -- or manually loading a session
    vim.api.nvim_create_autocmd(M.opts.autoload.events, {
      desc = 'Load nvim session automatically on UI attachment.',
      group = groupid,
      once = true,
      callback = function()
        if
          not vim.g._session_loaded
          and not vim.g._session_disabled
          and vim.deep_equal(vim.v.argv, { 'nvim', '--embed' })
        then
          M.load()
        end
      end,
    })
  end

  if check_enabled(M.opts.autoremove) then
    vim.api.nvim_create_autocmd(M.opts.autoremove.events, {
      group = vim.api.nvim_create_augroup('SessionAutoRemove', {}),
      desc = 'Automatically remove sessions.',
      callback = vim.schedule_wrap(function()
        if M.opts.autoremove.cond() then
          M.remove()
        end
      end),
    })
  end

  -- Create user commands
  vim.api.nvim_create_user_command('SessionLoad', cmd(M.load), {
    desc = 'Load session.',
    nargs = '?',
    complete = cmp,
  })

  vim.api.nvim_create_user_command('SessionSave', cmd(M.save), {
    desc = 'Save current state to given session.',
    nargs = '?',
    complete = cmp,
  })

  vim.api.nvim_create_user_command('Mksession', cmd(M.save), {
    desc = 'Save current state to given session.',
    nargs = '?',
    complete = cmp,
  })

  vim.api.nvim_create_user_command('SessionRemove', cmd(M.remove), {
    desc = 'Remove session.',
    nargs = '?',
    complete = cmp,
  })

  vim.api.nvim_create_user_command('SessionSelect', M.select, {
    desc = 'Interactively select and load session.',
  })
end

return M
