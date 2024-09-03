-- Disable auto session saving and loading in headless mode
if not vim.g.has_ui then
  return
end

local session_dir =
  vim.fs.joinpath(vim.fn.stdpath('cache') --[[@as string]], 'session')

if not vim.uv.fs_stat(session_dir) then
  vim.fn.mkdir(session_dir, 'p')
end

---Get session file path
---@return string
local function get_session()
  return vim.fs.joinpath(
    session_dir,
    vim.fs.normalize(vim.fn.getcwd(0)):gsub('%%', '%%%%'):gsub('/', '%%')
      .. '.vim'
  )
end

---Save current session
---@return nil
local function save_session()
  vim.cmd.mksession({
    vim.fn.fnameescape(get_session()),
    bang = true,
    mods = {
      silent = true,
      emsg_silent = true,
    },
  })
end

---Remove the loaded session file
---@return nil
local function remove_session()
  if vim.g._session_loaded then
    vim.fn.delete(vim.g._session_loaded)
    vim.g._session_loaded = nil
  end
end

---Load current session
---@return nil
local function load_session()
  local session = get_session()
  if not vim.uv.fs_stat(session) then
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

---Check if there is any named buffer
---Note: temp files, (gitcommit, gitrebase, and files under /tmp) and hidden
---unlisted buffers are ignored
---@return boolean?
local function has_named_buffer()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.fn.buflisted(buf) == 0 and vim.fn.bufwinid(buf) == -1 then
      goto continue
    end
    local bt = vim.bo[buf].bt
    if bt == 'terminal' or bt == 'quickfix' or bt == 'prompt' then
      goto continue
    end
    local ft = vim.bo[buf].ft
    if ft == 'gitcommit' or ft == 'gitrebase' then
      goto continue
    end
    local bufname = vim.api.nvim_buf_get_name(buf)
    if vim.startswith(bufname, '/tmp/') then
      goto continue
    end

    if bufname ~= '' then
      return true
    end
    ::continue::
  end
end

-- Wait for buffer options & names to be set before checking for named buffers
-- and saving the session
vim.schedule(function()
  if has_named_buffer() then
    save_session()
  end
end)

local groupid = vim.api.nvim_create_augroup('Session', {})
vim.api.nvim_create_autocmd({
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
}, {
  group = groupid,
  desc = 'Automatically save session.',
  -- `BufDelete` event triggers just before the buffers is actually deleted from
  -- the buffer list, delay to ensure that the buffer is deleted before checking
  -- for named buffers
  callback = vim.schedule_wrap(function()
    if has_named_buffer() then
      save_session()
    else
      -- Remove current session if all 'file' buffers
      -- are deleted in the current nvim process
      remove_session()
    end
  end),
})

vim.api.nvim_create_autocmd({ 'StdinReadPre', 'SessionLoadPost' }, {
  once = true,
  group = groupid,
  desc = 'Detect stdin or manual session loading to disable automatic session loading.',
  callback = function()
    vim.g._session_disable = true
    return true
  end,
})

-- Load session on UI attachment
-- Don't load session if there is no argument, piping from stdin,
-- or manually loading a session
vim.api.nvim_create_autocmd('UIEnter', {
  once = true,
  group = groupid,
  desc = 'Load nvim session automatically on UI attachment.',
  callback = function()
    if not vim.deep_equal(vim.v.argv, { 'nvim', '--embed' }) then
      return true
    end
    if vim.g._session_disable then
      vim.g._session_disable = nil
      return true
    end
    load_session()
    return true
  end,
})
