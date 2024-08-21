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
    vim.fs.normalize(vim.fn.getcwd(-1)):gsub('%%', '%%%%'):gsub('/', '%%')
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

---Remove session file
---@return nil
local function remove_session()
  vim.fn.delete(get_session())
end

---Load current session
---@return nil
local function load_session()
  local session = get_session()
  if not vim.uv.fs_stat(session) then
    return
  end

  -- Avoid intro message flickering before loading session,
  -- see `plugin/intro.lua` and `:h :intro`
  vim.opt.shortmess:append('I')
  vim.api.nvim_exec_autocmds('WinEnter', {})

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
---Note: temp files, e.g. gitcommit, gitrebase, and files under /tmp are ignored
---@return boolean?
local function has_named_buffer()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if not vim.api.nvim_buf_is_valid(buf) then
      goto continue
    end
    local filetype = vim.bo[buf].filetype
    if filetype == 'gitcommit' or filetype == 'gitrebase' then
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

if has_named_buffer() then
  save_session()
end

local groupid = vim.api.nvim_create_augroup('Session', {})
vim.api.nvim_create_autocmd({
  'BufNew',
  'BufNewFile',
  'BufDelete',
  'TermOpen',
  'TermClose',
  'WinNew',
  'WinClosed',
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
