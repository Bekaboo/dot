local fzf = require('fzf-lua')
local actions = require('fzf-lua.actions')
local core = require('fzf-lua.core')
local path = require('fzf-lua.path')
local config = require('fzf-lua.config')
local utils = require('utils')
local icons = require('utils.static.icons')

local _arg_del = actions.arg_del
local _vimcmd_buf = actions.vimcmd_buf

---@diagnostic disable-next-line: duplicate-set-field
function actions.arg_del(...)
  pcall(_arg_del, ...)
end

---@diagnostic disable-next-line: duplicate-set-field
function actions.vimcmd_buf(...)
  pcall(_vimcmd_buf, ...)
end

local _mt_cmd_wrapper = core.mt_cmd_wrapper

---Wrap `core.mt_cmd_wrapper()` used in fzf-lua's file and grep providers
---to ignore `opts.cwd` when generating the command string because once the
---cwd is hard-coded in the command string, `opts.cwd` will be ignored.
---
---This fixes the bug where `change_cwd()` does not work if it is used after
---`switch_provider()`:
---
---In `switch_provider()`, `opts.cwd` will be passed the corresponding fzf
---provider (file or grep) where it will be compiled in the command string,
---which will then be stored in `fzf.config.__resume_data.contents`.
---
---`change_cwd()` internally calls the resume action to resume the last
---provider and reuse other info in previous fzf session (e.g. last query, etc)
---except `opts.cwd`, `opts.fn_selected`, etc. that needs to be changed to
---reflect the new cwd.
---
---Thus if `__resume_data.contents` contains information about the previous
---cwd, the new cwd in `opts.cwd` will be ignored and `change_cwd()` will not
---take effect.
---@param opts table?
---@diagnostic disable-next-line: duplicate-set-field
function core.mt_cmd_wrapper(opts)
  if not opts or not opts.cwd then
    return _mt_cmd_wrapper(opts)
  end
  local _opts = {}
  for k, v in pairs(opts) do
    _opts[k] = v
  end
  _opts.cwd = nil
  return _mt_cmd_wrapper(_opts)
end

---Switch provider while preserving the last query and cwd
---@return nil
function actions.switch_provider()
  local opts = {
    query = fzf.config.__resume_data.last_query,
    cwd = fzf.config.__resume_data.opts.cwd,
  }
  fzf.builtin({
    actions = {
      ['enter'] = function(selected)
        fzf[selected[1]](opts)
      end,
      ['esc'] = actions.resume,
    },
  })
end

---Change cwd while preserving the last query
---@return nil
function actions.change_cwd()
  local resume_data = vim.deepcopy(fzf.config.__resume_data)
  resume_data.opts = resume_data.opts or {}

  -- Remove old fn_selected, else selected item will be opened
  -- with previous cwd
  local opts = resume_data.opts
  opts.fn_selected = nil
  opts.cwd = opts.cwd or vim.uv.cwd()
  opts.query = fzf.config.__resume_data.last_query

  local at_home = utils.fs.contains('~', opts.cwd)
  fzf.files({
    cwd_prompt = false,
    prompt = 'New cwd: ' .. (at_home and '~/' or '/'),
    cwd = at_home and '~' or '/',
    query = vim.fn
      .fnamemodify(opts.cwd, at_home and ':~' or ':p')
      :gsub('^~', '')
      :gsub('^/', ''),
    -- Append current dir './' to the result list to allow switching to home
    -- or root directory
    cmd = string.format(
      "%s | sed '1i\\\n./\n'",
      (function()
        local fd_cmd = vim.fn.executable('fd') == 1 and 'fd'
          or vim.fn.executable('fdfind') == 1 and 'fdfind'
          or nil

        if not fd_cmd then
          return [[find -L * -type d -print0 | xargs -0 ls -Fd]]
        end

        local grep_cmd = vim.fn.executable('rg') == 1 and 'rg' or 'grep'
        return string.format(
          [[%s --hidden --follow --type d --type l | %s /$]],
          fd_cmd,
          grep_cmd
        )
      end)()
    ),
    fzf_opts = { ['--no-multi'] = true },
    actions = {
      ['enter'] = function(selected)
        if not selected[1] then
          return
        end

        opts.cwd = vim.fs.normalize(
          vim.fs.joinpath(
            at_home and '~' or '/',
            path.entry_to_file(selected[1]).path
          )
        )

        -- Adapted from fzf-lua `core.set_header()` function
        if opts.cwd_prompt then
          opts.prompt = vim.fn.fnamemodify(opts.cwd, ':~')
          local shorten_len = tonumber(opts.cwd_prompt_shorten_len)
          if shorten_len and #opts.prompt >= shorten_len then
            opts.prompt = path.shorten(
              opts.prompt,
              tonumber(opts.cwd_prompt_shorten_val) or 1
            )
          end
          if not path.ends_with_separator(opts.prompt) then
            opts.prompt = opts.prompt .. path.separator()
          end
        end

        if opts.headers then
          opts = core.set_header(opts, opts.headers)
        end

        fzf.config.__resume_data = resume_data
        actions.resume()
      end,
      ['esc'] = function()
        fzf.config.__resume_data = resume_data
        actions.resume()
      end,
      -- Should not change dir or exclude dirs when selecting cwd
      ['alt-c'] = false,
      ['alt-/'] = false,
    },
  })
end

---Include directories, not only files when using the `files` picker
---@return nil
function actions.toggle_dir(_, opts)
  local exe = opts.cmd:match('^%s*(%S+)')
  local flag = opts.toggle_dir_flag
    or (exe == 'fd' or exe == 'fdfind') and '--type d'
    or (exe == 'find') and '-type d'
    or ''
  actions.toggle_flag(_, vim.tbl_extend('force', opts, { toggle_flag = flag }))
end

---Delete selected autocmd
---@return nil
function actions.del_autocmd(selected)
  for _, line in ipairs(selected) do
    local event, group, pattern =
      line:match('^.+:%d+:|(%w+)%s*│%s*(%S+)%s*│%s*(.-)%s*│')
    if event and group and pattern then
      vim.cmd.autocmd({
        bang = true,
        args = { group, event, pattern },
        mods = { emsg_silent = true },
      })
    end
  end
  local query = fzf.config.__resume_data.last_query
  fzf.autocmds({
    fzf_opts = {
      ['--query'] = query ~= '' and query or nil,
    },
  })
end

---Search & select files then add them to arglist
---@return nil
function actions.arg_search_add()
  local opts = fzf.config.__resume_data.opts
  fzf.files({
    cwd_header = true,
    cwd_prompt = false,
    prompt = 'Argadd> ',
    actions = {
      ['enter'] = function(selected, o)
        local cmd = 'argadd'
        vim.ui.input({
          prompt = 'Argadd cmd: ',
          default = cmd,
        }, function(input)
          if input then
            cmd = input
          end
        end)
        actions.vimcmd_file(cmd, selected, o)
        fzf.args(opts)
      end,
      ['esc'] = function()
        fzf.args(opts)
      end,
    },
    find_opts = [[-type f -not -path '*/\.git/*' -not -path '*/\.venv/*' -printf '%P\n']],
    fd_opts = [[--color=never --type f --type l --hidden --follow --exclude .git]],
    rg_opts = [[--color=never --files --hidden --follow -g '!.git']],
  })
end

local _file_split = actions.file_split
local _file_vsplit = actions.file_vsplit
local _file_tabedit = actions.file_tabedit
local _file_sel_to_qf = actions.file_sel_to_qf
local _file_sel_to_ll = actions.file_sel_to_ll
local _buf_split = actions.buf_split
local _buf_vsplit = actions.buf_vsplit
local _buf_tabedit = actions.buf_tabedit

---@diagnostic disable-next-line: duplicate-set-field
function actions.file_split(...)
  local win = vim.api.nvim_get_current_win()
  _file_split(...)
  if vim.api.nvim_win_is_valid(win) and utils.win.is_empty(win) then
    vim.api.nvim_win_close(win, false)
  end
end

---@diagnostic disable-next-line: duplicate-set-field
function actions.file_vsplit(...)
  local win = vim.api.nvim_get_current_win()
  _file_vsplit(...)
  if vim.api.nvim_win_is_valid(win) and utils.win.is_empty(win) then
    vim.api.nvim_win_close(win, false)
  end
end

---@diagnostic disable-next-line: duplicate-set-field
function actions.file_tabedit(...)
  local tab = vim.api.nvim_get_current_tabpage()
  _file_tabedit(...)
  if vim.api.nvim_tabpage_is_valid(tab) and utils.tab.is_empty(tab) then
    vim.api.nvim_win_close(vim.api.nvim_tabpage_list_wins(tab)[1], false)
  end
end

---@diagnostic disable-next-line: duplicate-set-field
function actions.file_edit_or_qf(selected, opts)
  if #selected > 1 then
    actions.file_sel_to_qf(selected, opts)
    vim.cmd.cfirst()
    vim.cmd.copen()
  else
    -- Fix oil buffer concealing issue when opening some dirs
    vim.schedule(function()
      actions.file_edit(selected, opts)
    end)
  end
end

---@diagnostic disable-next-line: duplicate-set-field
function actions.file_sel_to_qf(selected, opts)
  _file_sel_to_qf(selected, opts)
  if #selected > 1 then
    vim.cmd.cfirst()
    vim.cmd.copen()
  end
end

---@diagnostic disable-next-line: duplicate-set-field
function actions.file_sel_to_ll(selected, opts)
  _file_sel_to_ll(selected, opts)
  if #selected > 1 then
    vim.cmd.lfirst()
    vim.cmd.lopen()
  end
end

---@diagnostic disable-next-line: duplicate-set-field
function actions.buf_split(...)
  local win = vim.api.nvim_get_current_win()
  _buf_split(...)
  if vim.api.nvim_win_is_valid(win) and utils.win.is_empty(win) then
    vim.api.nvim_win_close(win, false)
  end
end

---@diagnostic disable-next-line: duplicate-set-field
function actions.buf_vsplit(...)
  local win = vim.api.nvim_get_current_win()
  _buf_vsplit(...)
  if vim.api.nvim_win_is_valid(win) and utils.win.is_empty(win) then
    vim.api.nvim_win_close(win, false)
  end
end

---@diagnostic disable-next-line: duplicate-set-field
function actions.buf_tabedit(...)
  local tab = vim.api.nvim_get_current_tabpage()
  _buf_tabedit(...)
  if vim.api.nvim_tabpage_is_valid(tab) and utils.tab.is_empty(tab) then
    vim.api.nvim_win_close(vim.api.nvim_tabpage_list_wins(tab)[1], false)
  end
end

function actions.insert_register(...)
  actions.paste_register(...)
  vim.api.nvim_feedkeys('a', 'n', true)
end

core.ACTION_DEFINITIONS[actions.toggle_dir] = {
  function(o)
    -- When using `fd` the flag is '--type d', but for `find` the flag is
    -- '-type d', use '-type d' as default flag here anyway since it is
    -- the common substring for both `find` and `fd` commands
    local flag = o.toggle_dir_flag or '-type d'
    local escape = require('fzf-lua.utils').lua_regex_escape
    return o.cmd and o.cmd:match(escape(flag)) and 'Exclude dirs'
      or 'Include dirs'
  end,
}
core.ACTION_DEFINITIONS[actions.change_cwd] = { 'Change cwd', pos = 1 }
core.ACTION_DEFINITIONS[actions.arg_del] = { 'delete' }
core.ACTION_DEFINITIONS[actions.del_autocmd] = { 'delete autocmd' }
core.ACTION_DEFINITIONS[actions.arg_search_add] = { 'add new file' }
core.ACTION_DEFINITIONS[actions.search] = { 'edit' }
core.ACTION_DEFINITIONS[actions.ex_run] = { 'edit' }
core.ACTION_DEFINITIONS[actions.insert_register] = { 'insert register' }

config._action_to_helpstr[actions.toggle_dir] = 'toggle-dir'
config._action_to_helpstr[actions.switch_provider] = 'switch-provider'
config._action_to_helpstr[actions.change_cwd] = 'change-cwd'
config._action_to_helpstr[actions.arg_del] = 'delete'
config._action_to_helpstr[actions.del_autocmd] = 'delete-autocmd'
config._action_to_helpstr[actions.arg_search_add] = 'search-and-add-new-file'
config._action_to_helpstr[actions.file_split] = 'file-split'
config._action_to_helpstr[actions.file_vsplit] = 'file-vsplit'
config._action_to_helpstr[actions.file_tabedit] = 'file-tabedit'
config._action_to_helpstr[actions.file_edit_or_qf] = 'file-edit-or-qf'
config._action_to_helpstr[actions.file_sel_to_qf] = 'file-select-to-quickfix'
config._action_to_helpstr[actions.file_sel_to_ll] = 'file-select-to-loclist'
config._action_to_helpstr[actions.buf_split] = 'buffer-split'
config._action_to_helpstr[actions.buf_vsplit] = 'buffer-vsplit'
config._action_to_helpstr[actions.buf_tabedit] = 'buffer-tabedit'
config._action_to_helpstr[actions.buf_edit_or_qf] = 'buffer-edit-or-qf'
config._action_to_helpstr[actions.buf_sel_to_qf] = 'buffer-select-to-quickfix'
config._action_to_helpstr[actions.buf_sel_to_ll] = 'buffer-select-to-loclist'
config._action_to_helpstr[actions.insert_register] = 'insert-register'

-- Use different prompts for document and workspace diagnostics
-- by overriding `fzf.diagnostics_workspace()` and `fzf.diagnostics_document()`
-- because fzf-lua does not support setting different prompts for them via
-- the `fzf.setup()` function, see `defaults.lua` & `providers/diagnostic.lua`
local _diagnostics_workspace = fzf.diagnostics_workspace
local _diagnostics_document = fzf.diagnostics_document

---@param opts table?
function fzf.diagnostics_document(opts)
  return _diagnostics_document(vim.tbl_extend('force', opts or {}, {
    prompt = 'Document Diagnostics> ',
  }))
end

---@param opts table?
function fzf.diagnostics_workspace(opts)
  return _diagnostics_workspace(vim.tbl_extend('force', opts or {}, {
    prompt = 'Workspace Diagnostics> ',
  }))
end

---Search symbols, fallback to treesitter nodes if no language server
---supporting symbol method is attached
function fzf.symbols(opts)
  if
    vim.tbl_isempty(vim.lsp.get_clients({
      bufnr = 0,
      method = 'textDocument/documentSymbol',
    }))
  then
    return fzf.treesitter(opts)
  end
  return fzf.lsp_document_symbols(opts)
end

-- Override `vim.lsp.buf.document_symbol()` to use `fzf.symbols()`
-- which fallback to treesitter nodes if no symbols are provided
-- by attached language servers
vim.lsp.buf.document_symbol = fzf.symbols

-- Overriding `vim.lsp.buf.workspace_symbol()`, not only the handler here
-- to skip the 'Query:' input prompt -- with `fzf.lsp_live_workspace_symbols()`
-- as handler we can update the query in live
local _lsp_workspace_symbol = vim.lsp.buf.workspace_symbol

---@diagnostic disable-next-line: duplicate-set-field
function vim.lsp.buf.workspace_symbol(query, options)
  _lsp_workspace_symbol(query or '', options)
end

vim.lsp.buf.incoming_calls = fzf.lsp_incoming_calls
vim.lsp.buf.outgoing_calls = fzf.lsp_outgoing_calls
vim.lsp.buf.declaration = fzf.declarations
vim.lsp.buf.definition = fzf.lsp_definitions
vim.lsp.buf.document_symbol = fzf.lsp_document_symbols
vim.lsp.buf.implementation = fzf.lsp_implementations
vim.lsp.buf.references = fzf.lsp_references
vim.lsp.buf.type_definition = fzf.lsp_typedefs
vim.lsp.buf.workspace_symbol = fzf.lsp_live_workspace_symbols

vim.diagnostic.setqflist = fzf.diagnostics_workspace
vim.diagnostic.setloclist = fzf.diagnostics_document

-- Fix fzf-lua's bug of not using source window's current cwd
-- when used in conjunction with auto-cwd autocmd
-- TODO: report to upstream
local _fzf_files = fzf.files

---@param opts table?
function fzf.files(opts)
  opts = opts or {}
  opts.cwd = opts.cwd or vim.fn.getcwd(0)
  return _fzf_files(opts)
end

-- Select dirs from `z`
---@param opts table?
function fzf.z(opts)
  local has_z_plugin, z = pcall(require, 'plugin.z')
  if not has_z_plugin then
    vim.notify('[Fzf-lua] z plugin not found')
    return
  end

  -- Register action descriptions
  actions.z = z.jump
  core.ACTION_DEFINITIONS[actions.z] = { 'jump to dir' }
  config._action_to_helpstr[actions.z] = 'jump-to-dir'

  return fzf.fzf_exec(
    z.list(),
    vim.tbl_deep_extend('force', opts or {}, {
      cwd = vim.fn.getcwd(0),
      prompt = 'Open directory: ',
      actions = {
        ['enter'] = actions.z,
      },
      fzf_opts = {
        ['--no-multi'] = true,
      },
    })
  )
end

-- Select/remove sessions from the session plugin
---@param opts table?
function fzf.sessions(opts)
  local has_session_plugin, session = pcall(require, 'plugin.session')
  if not has_session_plugin then
    vim.notify('[Fzf-lua] session plugin not found')
    return
  end

  if vim.fn.executable('ls') == 0 then
    vim.notify('[Fzf-lua] `ls` command not available')
    return
  end

  ---Get keymap action
  ---@param cb fun(path?: string) session operation function (load, remove, etc.)
  ---@return fun(selected: string[])
  local function action(cb)
    return function(selected)
      vim.iter(selected):each(function(dir)
        cb(vim.fs.joinpath(session.opts.dir, session.dir2session(dir)))
      end)
    end
  end

  -- Register action descriptions
  actions.load_session = action(session.load)
  core.ACTION_DEFINITIONS[actions.load_session] = { 'load session' }
  config._action_to_helpstr[actions.load_session] = 'load-session'

  actions.remove_session = action(session.remove)
  core.ACTION_DEFINITIONS[actions.remove_session] = { 'remove session' }
  config._action_to_helpstr[actions.remove_session] = 'remove-session'

  return fzf.fzf_exec(
    string.format(
      [[ls -1 %s | while read -r file; do mod="${file//%%//}"; echo "${mod//\/\//%%}"; done]],
      session.opts.dir
    ),
    vim.tbl_deep_extend('force', opts or {}, {
      prompt = 'Sessions: ',
      actions = {
        ['enter'] = actions.load_session,
        ['ctrl-x'] = {
          fn = actions.remove_session,
          reload = true,
        },
      },
    })
  )
end

---Fuzzy complete cmdline command/search history
---@param opts table?
function fzf.complete_cmdline(opts)
  opts = opts or {}
  opts.query = vim.fn.getcmdline()
  vim.api.nvim_feedkeys(vim.keycode('<C-\\><C-n>'), 'n', true)

  local type = vim.fn.getcmdtype()
  if type == ':' then
    fzf.command_history(opts)
    return
  end
  if type == '/' or type == '?' then
    opts.reverse_search = type == '?'
    fzf.search_history(opts)
    return
  end
end

---Fuzzy complete from registers in insert mode
---@param opts table?
function fzf.complete_from_registers(opts)
  fzf.registers(vim.tbl_deep_extend('force', opts or {}, {
    actions = {
      ['enter'] = actions.insert_register,
    },
  }))
end

_G._fzf_lua_win_views = {}
_G._fzf_lua_win_heights = {}

fzf.setup({
  -- Default profile 'default-title' disables prompt in favor of title
  -- on nvim >= 0.9, but a fzf windows with split layout cannot have titles
  -- See https://github.com/ibhagwan/fzf-lua/issues/1739
  'default-prompt',
  -- Use nbsp in tty to avoid showing box chars
  nbsp = not vim.go.termguicolors and '\xc2\xa0' or nil,
  dir_icon = vim.trim(icons.Folder),
  winopts = {
    backdrop = 100,
    -- Split at bottom, save information for restoration in
    -- `winopts.on_close()` callback
    split = [[
      call v:lua.require'utils.win'.save_heights('_fzf_lua_win_heights') |
        \ call v:lua.require'utils.win'.save_views('_fzf_lua_win_views') |
        \ let g:_fzf_vim_lines = &lines |
        \ let g:_fzf_leave_win = win_getid(winnr()) |
        \ let g:_fzf_splitkeep = &splitkeep | let &splitkeep = "topline" |
        \ let g:_fzf_cmdheight = &cmdheight | let &cmdheight = 0 |
        \ let g:_fzf_laststatus = &laststatus | let &laststatus = 0 |
        \ let g:_fzf_height = 10 |
        \ let g:_fzf_qfclosed = win_gettype(winnr('$')) |
        \ if g:_fzf_qfclosed ==# 'loclist' || g:_fzf_qfclosed ==# 'quickfix' |
        \   let g:_fzf_height = nvim_win_get_height(win_getid(winnr('$'))) - 1 |
        \   cclose |
        \   lclose |
        \ else |
        \   unlet g:_fzf_qfclosed |
        \ endif |
        \ exe printf('botright %dnew', g:_fzf_height) |
        \ exe 'resize' . (g:_fzf_height + g:_fzf_cmdheight + (g:_fzf_laststatus ? 1 : 0)) |
        \ let w:winbar_no_attach = v:true |
        \ setlocal bt=nofile bh=wipe nobl noswf
    ]],
    on_create = function()
      vim.keymap.set(
        't',
        '<C-r>',
        [['<C-\><C-N>"' . nr2char(getchar()) . 'pi']],
        {
          expr = true,
          buffer = true,
          desc = 'Insert contents in a register',
        }
      )
      -- Sometimes windows will shift/change size after closing quickfix window
      -- and reopening fzf, maybe related to https://github.com/neovim/neovim/issues/30955
      if vim.g._fzf_qfclosed then
        utils.win.restore_heights(_G._fzf_lua_win_heights)
        utils.win.restore_views(_G._fzf_lua_win_views)
      end
    end,
    on_close = function()
      ---@param name string
      ---@return nil
      local function _restore_global_opt(name)
        local backup_name = '_fzf_' .. name
        local backup = vim.g[backup_name]
        if backup ~= nil and vim.go[name] ~= backup then
          vim.go[name] = backup
          vim.g[backup_name] = nil
        end
      end

      _restore_global_opt('splitkeep')
      _restore_global_opt('cmdheight')
      _restore_global_opt('laststatus')

      -- Reopen quickfix/location list after closing fzf if we previous closed
      -- it to make space for fzf
      local win = vim.api.nvim_get_current_win()
      if vim.g._fzf_qfclosed == 'loclist' then
        vim.cmd.lopen()
      elseif vim.g._fzf_qfclosed == 'quickfix' then
        vim.cmd.copen()
      end
      vim.g._fzf_qfclosed = nil
      if
        win ~= vim.api.nvim_get_current_win()
        and vim.api.nvim_win_is_valid(win)
      then
        vim.api.nvim_set_current_win(win)
      end

      if
        vim.g._fzf_leave_win
        and vim.api.nvim_win_is_valid(vim.g._fzf_leave_win)
        and vim.api.nvim_get_current_win() ~= vim.g._fzf_leave_win
      then
        vim.api.nvim_set_current_win(vim.g._fzf_leave_win)
      end
      vim.g._fzf_leave_win = nil

      if vim.go.lines == vim.g._fzf_vim_lines then
        utils.win.restore_heights(_G._fzf_lua_win_heights)
      end
      vim.g._fzf_vim_lines = nil
      _G._fzf_lua_win_heights = {}

      utils.win.restore_views(_G._fzf_lua_win_views)
      _G._fzf_lua_win_views = {}
    end,
    preview = {
      border = 'none',
      hidden = 'hidden',
      layout = 'horizontal',
      scrollbar = false,
    },
  },
  -- Open help window at top of screen with single border
  help_open_win = function(buf, enter, opts)
    opts.border = 'single'
    opts.row = 0
    opts.col = 0
    return vim.api.nvim_open_win(buf, enter, opts)
  end,
  hls = {
    title = 'TelescopeTitle',
    preview_title = 'TelescopeTitle',
    -- Builtin preview only
    cursor = 'Cursor',
    cursorline = 'TelescopePreviewLine',
    cursorlinenr = 'TelescopePreviewLine',
    search = 'IncSearch',
  },
  fzf_colors = {
    ['hl'] = { 'fg', 'TelescopeMatching' },
    ['fg+'] = { 'fg', 'TelescopeSelection' },
    ['bg+'] = { 'bg', 'TelescopeSelection' },
    ['hl+'] = { 'fg', 'TelescopeMatching' },
    ['info'] = { 'fg', 'TelescopeCounter' },
    ['prompt'] = { 'fg', 'TelescopePrefix' },
    ['pointer'] = { 'fg', 'TelescopeSelectionCaret' },
    ['marker'] = { 'fg', 'TelescopeMultiIcon' },
    ['fg'] = { 'fg', 'TelescopeNormal' },
    ['bg'] = '-1',
    ['gutter'] = '-1',
  },
  keymap = {
    -- Overrides default completion completely
    builtin = {
      ['<C-_>'] = 'toggle-help',
      ['<F1>'] = 'toggle-help',
      ['<F2>'] = 'toggle-fullscreen',
    },
    fzf = {
      -- fzf '--bind=' options
      ['ctrl-z'] = 'abort',
      ['ctrl-k'] = 'kill-line',
      ['ctrl-u'] = 'unix-line-discard',
      ['ctrl-a'] = 'beginning-of-line',
      ['ctrl-e'] = 'end-of-line',
      ['alt-a'] = 'toggle-all',
      ['alt-}'] = 'last',
      ['alt-{'] = 'first',
    },
  },
  actions = {
    files = {
      ['alt-s'] = actions.file_split,
      ['alt-v'] = actions.file_vsplit,
      ['alt-t'] = actions.file_tabedit,
      ['alt-q'] = actions.file_sel_to_qf,
      ['alt-l'] = actions.file_sel_to_ll,
      ['enter'] = actions.file_edit_or_qf,
    },
    buffers = {
      ['alt-s'] = actions.buf_split,
      ['alt-v'] = actions.buf_vsplit,
      ['alt-t'] = actions.buf_tabedit,
      ['enter'] = actions.buf_edit_or_qf,
    },
  },
  defaults = {
    actions = {
      ['ctrl-]'] = actions.switch_provider,
    },
  },
  args = {
    files_only = false,
    actions = {
      ['ctrl-s'] = actions.arg_search_add,
      ['ctrl-x'] = {
        fn = actions.arg_del,
        reload = true,
      },
    },
  },
  autocmds = {
    actions = {
      ['ctrl-x'] = {
        fn = actions.del_autocmd,
        -- reload = true,
      },
    },
  },
  blines = {
    actions = {
      ['alt-q'] = actions.buf_sel_to_qf,
      ['alt-l'] = actions.buf_sel_to_ll,
    },
  },
  lines = {
    actions = {
      ['alt-q'] = actions.buf_sel_to_qf,
      ['alt-l'] = actions.buf_sel_to_ll,
    },
  },
  buffers = {
    show_unlisted = false,
    show_unloaded = true,
    ignore_current_buffer = false,
    no_action_set_cursor = true,
    current_tab_only = false,
    no_term_buffers = false,
    cwd_only = false,
    ls_cmd = 'ls',
  },
  helptags = {
    actions = {
      ['enter'] = actions.help,
      ['alt-s'] = actions.help,
      ['alt-v'] = actions.help_vert,
      ['alt-t'] = actions.help_tab,
    },
  },
  manpages = {
    actions = {
      ['enter'] = actions.man,
      ['alt-s'] = actions.man,
      ['alt-v'] = actions.man_vert,
      ['alt-t'] = actions.man_tab,
    },
  },
  keymaps = {
    actions = {
      ['enter'] = actions.keymap_edit,
      ['alt-s'] = actions.keymap_split,
      ['alt-v'] = actions.keymap_vsplit,
      ['alt-t'] = actions.keymap_tabedit,
    },
  },
  colorschemes = {
    actions = {
      ['enter'] = actions.colorscheme,
    },
  },
  command_history = {
    actions = {
      ['enter'] = actions.ex_run,
      ['ctrl-e'] = false,
    },
  },
  search_history = {
    actions = {
      ['enter'] = actions.search,
      ['ctrl-e'] = false,
    },
  },
  files = {
    actions = {
      ['alt-c'] = actions.change_cwd,
      ['alt-h'] = actions.toggle_hidden,
      ['alt-i'] = actions.toggle_ignore,
      ['alt-/'] = actions.toggle_dir,
      ['ctrl-g'] = false,
    },
    fzf_opts = {
      ['--info'] = 'inline-right',
    },
    find_opts = [[-type f -not -path '*/\.git/*' -not -path '*/\.venv/*' -printf '%P\n']],
    fd_opts = [[--color=never --type f --type l --hidden --follow --exclude .git --exclude .venv]],
    rg_opts = [[--no-messages --color=never --files --hidden --follow -g '!.git' -g '!.venv']],
  },
  oldfiles = {
    prompt = 'Oldfiles> ',
  },
  git = {
    commits = {
      prompt = 'GitLogs>',
      actions = {
        ['enter'] = actions.git_buf_edit,
        ['alt-s'] = actions.git_buf_split,
        ['alt-v'] = actions.git_buf_vsplit,
        ['alt-t'] = actions.git_buf_tabedit,
        ['ctrl-y'] = { fn = actions.git_yank_commit, exec_silent = true },
      },
    },
    bcommits = {
      prompt = 'GitBLogs>',
      actions = {
        ['enter'] = actions.git_buf_edit,
        ['alt-s'] = actions.git_buf_split,
        ['alt-v'] = actions.git_buf_vsplit,
        ['alt-t'] = actions.git_buf_tabedit,
        ['ctrl-y'] = { fn = actions.git_yank_commit, exec_silent = true },
      },
    },
    blame = {
      actions = {
        ['enter'] = actions.git_goto_line,
        ['alt-s'] = actions.git_buf_split,
        ['alt-v'] = actions.git_buf_vsplit,
        ['alt-t'] = actions.git_buf_tabedit,
        ['ctrl-y'] = { fn = actions.git_yank_commit, exec_silent = true },
      },
    },
    branches = {
      actions = {
        ['ctrl-s'] = {
          fn = actions.git_branch_add,
          field_index = '{q}',
          reload = true,
        },
      },
    },
  },
  fzf_opts = {
    ['--no-scrollbar'] = '',
    ['--no-separator'] = '',
    ['--info'] = 'inline-right',
    ['--layout'] = 'reverse',
    ['--no-unicode'] = not vim.g.has_nf,
    ['--marker'] = not vim.g.has_nf and icons.GitSignAdd or nil,
    ['--pointer'] = not vim.g.has_nf and icons.AngleRight or nil,
    ['--border'] = 'none',
    ['--padding'] = '0,1',
    ['--margin'] = '0',
  },
  grep = {
    rg_glob = true,
    actions = {
      ['alt-c'] = actions.change_cwd,
      ['alt-h'] = actions.toggle_hidden,
      ['alt-i'] = actions.toggle_ignore,
    },
    rg_opts = table.concat({
      '--no-messages',
      '--hidden',
      '--follow',
      '--smart-case',
      '--column',
      '--line-number',
      '--no-heading',
      '--color=always',
      '-g=!.git/',
      '-e',
    }, ' '),
    fzf_opts = {
      ['--info'] = 'inline-right',
    },
  },
  lsp = {
    jump1 = true,
    finder = {
      fzf_opts = {
        ['--info'] = 'inline-right',
      },
    },
    references = {
      sync = false,
      ignore_current_line = true,
    },
    definitions = { sync = false },
    typedefs = { sync = false },
    symbols = {
      symbol_style = vim.g.has_nf and 1 or 3,
      symbol_icons = vim.tbl_map(vim.trim, icons.kinds),
      symbol_hl = function(sym_name)
        return 'FzfLuaSym' .. sym_name
      end,
    },
  },
  diagnostics = {
    multiline = false,
  },
})

-- stylua: ignore start
vim.keymap.set('c', '<C-_>', fzf.complete_cmdline, { desc = 'Fuzzy complete command/search history' })
vim.keymap.set('c', '<C-x><C-l>', fzf.complete_cmdline, { desc = 'Fuzzy complete command/search history' })
vim.keymap.set('i', '<C-r>?', fzf.complete_from_registers, { desc = 'Fuzzy complete from registers' })
vim.keymap.set('i', '<C-r><C-_>', fzf.complete_from_registers, { desc = 'Fuzzy complete from registers' })
vim.keymap.set('i', '<C-r><C-r>', fzf.complete_from_registers, { desc = 'Fuzzy complete from registers' })
vim.keymap.set('i', '<C-x><C-f>', fzf.complete_path, { desc = 'Fuzzy complete path' })
vim.keymap.set('n', '<Leader>.', fzf.files, { desc = 'Find files' })
vim.keymap.set('n', "<Leader>'", fzf.resume, { desc = 'Resume last picker' })
vim.keymap.set('n', "<Leader>`", fzf.marks, { desc = 'Find marks' })
vim.keymap.set('n', '<Leader>,', fzf.buffers, { desc = 'Find buffers' })
vim.keymap.set('n', '<Leader>/', fzf.live_grep, { desc = 'Grep' })
vim.keymap.set('n', '<Leader>?', fzf.help_tags, { desc = 'Find help tags' })
vim.keymap.set('n', '<Leader>*', fzf.grep_cword, { desc = 'Grep word under cursor' })
vim.keymap.set('x', '<Leader>*', fzf.grep_visual, { desc = 'Grep visual selection' })
vim.keymap.set('n', '<Leader>#', fzf.grep_cword, { desc = 'Grep word under cursor' })
vim.keymap.set('x', '<Leader>#', fzf.grep_visual, { desc = 'Grep visual selection' })
vim.keymap.set('n', '<Leader>"', fzf.registers, { desc = 'Find registers' })
vim.keymap.set('n', '<Leader>:', fzf.commands, { desc = 'Find commands' })
vim.keymap.set('n', '<Leader>F', fzf.builtin, { desc = 'Find all available pickers' })
vim.keymap.set('n', '<Leader>o', fzf.oldfiles, { desc = 'Find old files' })
vim.keymap.set('n', '<Leader>-', fzf.blines, { desc = 'Find lines in buffer' })
vim.keymap.set('n', '<Leader>=', fzf.lines, { desc = 'Find lines across buffers' })
vim.keymap.set('x', '<Leader>-', fzf.blines, { desc = 'Find lines in selection' })
vim.keymap.set('x', '<Leader>=', fzf.blines, { desc = 'Find lines in selection' })
vim.keymap.set('n', '<Leader>n', fzf.treesitter, { desc = 'Find treesitter nodes' })
vim.keymap.set('n', '<Leader>R', fzf.lsp_finder, { desc = 'Find symbol locations' })
vim.keymap.set('n', '<Leader>f"', fzf.registers, { desc = 'Find registers' })
vim.keymap.set('n', '<Leader>f*', fzf.grep_cword, { desc = 'Grep word under cursor' })
vim.keymap.set('x', '<Leader>f*', fzf.grep_visual, { desc = 'Grep visual selection' })
vim.keymap.set('n', '<Leader>f#', fzf.grep_cword, { desc = 'Grep word under cursor' })
vim.keymap.set('x', '<Leader>f#', fzf.grep_visual, { desc = 'Grep visual selection' })
vim.keymap.set('n', '<Leader>f:', fzf.commands, { desc = 'Find commands' })
vim.keymap.set('n', '<Leader>f/', fzf.live_grep, { desc = 'Grep' })
vim.keymap.set('n', '<Leader>fH', fzf.highlights, { desc = 'Find highlights' })
vim.keymap.set('n', "<Leader>f'", fzf.resume, { desc = 'Resume last picker' })
vim.keymap.set('n', '<Leader>fA', fzf.autocmds, { desc = 'Find autocommands' })
vim.keymap.set('n', '<Leader>fb', fzf.buffers, { desc = 'Find buffers' })
vim.keymap.set('n', '<Leader>fp', fzf.tabs, { desc = 'Find tabpages' })
vim.keymap.set('n', '<Leader>ft', fzf.tags, { desc = 'Find tags' })
vim.keymap.set('n', '<Leader>fc', fzf.changes, { desc = 'Find changes' })
vim.keymap.set('n', '<Leader>fd', fzf.diagnostics_document, { desc = 'Find document diagnostics' })
vim.keymap.set('n', '<Leader>fD', fzf.diagnostics_workspace, { desc = 'Find workspace diagnostics' })
vim.keymap.set('n', '<Leader>ff', fzf.files, { desc = 'Find files' })
vim.keymap.set('n', '<Leader>fa', fzf.args, { desc = 'Find args' })
vim.keymap.set('n', '<Leader>fl', fzf.loclist, { desc = 'Find location list' })
vim.keymap.set('n', '<Leader>fq', fzf.quickfix, { desc = 'Find quickfix list' })
vim.keymap.set('n', '<Leader>fL', fzf.loclist_stack, { desc = 'Find location list stack' })
vim.keymap.set('n', '<Leader>fQ', fzf.quickfix_stack, { desc = 'Find quickfix stack' })
vim.keymap.set('n', '<Leader>fgt', fzf.git_tags, { desc = 'Find git tags' })
vim.keymap.set('n', '<Leader>fgs', fzf.git_stash, { desc = 'Find git stash' })
vim.keymap.set('n', '<Leader>fgg', fzf.git_status, { desc = 'Find git status' })
vim.keymap.set('n', '<Leader>fgL', fzf.git_commits, { desc = 'Find git logs' })
vim.keymap.set('n', '<Leader>fgl', fzf.git_bcommits, { desc = 'Find git buffer logs' })
vim.keymap.set('n', '<Leader>fgb', fzf.git_branches, { desc = 'Find git branches' })
vim.keymap.set('n', '<Leader>fgB', fzf.git_blame, { desc = 'Find git blame' })
vim.keymap.set('n', '<Leader>gft', fzf.git_tags, { desc = 'Find git tags' })
vim.keymap.set('n', '<Leader>gfs', fzf.git_stash, { desc = 'Find git stash' })
vim.keymap.set('n', '<Leader>gfg', fzf.git_status, { desc = 'Find git status' })
vim.keymap.set('n', '<Leader>gfL', fzf.git_commits, { desc = 'Find git logs' })
vim.keymap.set('n', '<Leader>gfl', fzf.git_bcommits, { desc = 'Find git buffer logs' })
vim.keymap.set('n', '<Leader>gfb', fzf.git_branches, { desc = 'Find git branches' })
vim.keymap.set('n', '<Leader>gfB', fzf.git_blame, { desc = 'Find git blame' })
vim.keymap.set('n', '<Leader>fh', fzf.help_tags, { desc = 'Find help tags' })
vim.keymap.set('n', '<Leader>fk', fzf.keymaps, { desc = 'Find keymaps' })
vim.keymap.set('n', '<Leader>f-', fzf.blines, { desc = 'Find lines in buffer' })
vim.keymap.set('x', '<Leader>f-', fzf.blines, { desc = 'Find lines in selection' })
vim.keymap.set('n', '<Leader>f=', fzf.lines, { desc = 'Find lines across buffers' })
vim.keymap.set('n', '<Leader>fm', fzf.marks, { desc = 'Find marks' })
vim.keymap.set('n', '<Leader>fo', fzf.oldfiles, { desc = 'Find old files' })
vim.keymap.set('n', '<Leader>fz', fzf.z, { desc = 'Find directories from z' })
vim.keymap.set('n', '<Leader>fw', fzf.sessions, { desc = 'Find sessions (workspaces)' })
vim.keymap.set('n', '<Leader>fn', fzf.treesitter, { desc = 'Find treesitter nodes' })
vim.keymap.set('n', '<Leader>fs', fzf.symbols, { desc = 'Find lsp symbols or treesitter nodes' })
vim.keymap.set('n', '<Leader>fSa', fzf.lsp_code_actions, { desc = 'Find code actions' })
vim.keymap.set('n', '<Leader>fSd', fzf.lsp_definitions, { desc = 'Find symbol definitions' })
vim.keymap.set('n', '<Leader>fSD', fzf.lsp_declarations, { desc = 'Find symbol declarations' })
vim.keymap.set('n', '<Leader>fS<C-d>', fzf.lsp_typedefs, { desc = 'Find symbol type definitions' })
vim.keymap.set('n', '<Leader>fSs', fzf.lsp_document_symbols, { desc = 'Find document symbols' })
vim.keymap.set('n', '<Leader>fSS', fzf.lsp_live_workspace_symbols, { desc = 'Find workspace symbols' })
vim.keymap.set('n', '<Leader>fSi', fzf.lsp_implementations, { desc = 'Find symbol implementations' })
vim.keymap.set('n', '<Leader>fS<', fzf.lsp_incoming_calls, { desc = 'Find symbol incoming calls' })
vim.keymap.set('n', '<Leader>fS>', fzf.lsp_outgoing_calls, { desc = 'Find symbol outgoing calls' })
vim.keymap.set('n', '<Leader>fSr', fzf.lsp_references, { desc = 'Find symbol references' })
vim.keymap.set('n', '<Leader>fSR', fzf.lsp_finder, { desc = 'Find symbol locations' })
vim.keymap.set('n', '<Leader>fF', fzf.builtin, { desc = 'Find all available pickers' })
vim.keymap.set('n', '<Leader>f<Esc>', '<Nop>', { desc = 'Cancel' })
-- stylua: ignore end

---Set telescope default hlgroups for a borderless view
---@return nil
local function set_default_hlgroups()
  local hl = utils.hl
  local hl_norm = hl.get(0, { name = 'Normal', link = false })
  local hl_special = hl.get(0, { name = 'Special', link = false })
  hl.set_default(0, 'FzfLuaSymDefault', { link = 'Special' })
  hl.set_default(0, 'FzfLuaSymArray', { link = 'Operator' })
  hl.set_default(0, 'FzfLuaSymBoolean', { link = 'Boolean' })
  hl.set_default(0, 'FzfLuaSymClass', { link = 'Type' })
  hl.set_default(0, 'FzfLuaSymConstant', { link = 'Constant' })
  hl.set_default(0, 'FzfLuaSymConstructor', { link = '@constructor' })
  hl.set_default(0, 'FzfLuaSymEnum', { link = 'Constant' })
  hl.set_default(0, 'FzfLuaSymEnumMember', { link = 'FzfLuaSymEnum' })
  hl.set_default(0, 'FzfLuaSymEvent', { link = '@lsp.type.event' })
  hl.set_default(0, 'FzfLuaSymField', { link = 'FzfLuaSymDefault' })
  hl.set_default(0, 'FzfLuaSymFile', { link = 'Directory' })
  hl.set_default(0, 'FzfLuaSymFunction', { link = 'Function' })
  hl.set_default(0, 'FzfLuaSymInterface', { link = 'Type' })
  hl.set_default(0, 'FzfLuaSymKey', { link = '@keyword' })
  hl.set_default(0, 'FzfLuaSymMethod', { link = 'Function' })
  hl.set_default(0, 'FzfLuaSymModule', { link = '@module' })
  hl.set_default(0, 'FzfLuaSymNamespace', { link = '@lsp.type.namespace' })
  hl.set_default(0, 'FzfLuaSymNull', { link = 'Constant' })
  hl.set_default(0, 'FzfLuaSymNumber', { link = 'Number' })
  hl.set_default(0, 'FzfLuaSymObject', { link = 'Statement' })
  hl.set_default(0, 'FzfLuaSymOperator', { link = 'Operator' })
  hl.set_default(0, 'FzfLuaSymPackage', { link = '@module' })
  hl.set_default(0, 'FzfLuaSymProperty', { link = 'FzfLuaSymDefault' })
  hl.set_default(0, 'FzfLuaSymString', { link = '@string' })
  hl.set_default(0, 'FzfLuaSymStruct', { link = 'Type' })
  hl.set_default(0, 'FzfLuaSymTypeParameter', { link = 'FzfLuaSymDefault' })
  hl.set_default(0, 'FzfLuaSymVariable', { link = 'FzfLuaSymDefault' })
  hl.set(0, 'FzfLuaBufFlagAlt', { link = 'FzfLuaSymDefault' })
  hl.set(0, 'FzfLuaBufFlagCur', { link = 'Operator' })
  hl.set(0, 'FzfLuaLiveSym', { link = 'WarningMsg' })
  hl.set(0, 'FzfLuaPathColNr', { link = 'FzfLuaSymDefault' })
  hl.set(0, 'FzfLuaPathLineNr', { link = 'FzfLuaSymDefault' })
  hl.set(0, 'FzfLuaBufFlagCur', {})
  hl.set(0, 'FzfLuaBufName', {})
  hl.set(0, 'FzfLuaBufNr', {})
  hl.set(0, 'FzfLuaBufLineNr', { link = 'LineNr' })
  hl.set(0, 'FzfLuaCursor', { link = 'None' })
  hl.set(0, 'FzfLuaHeaderBind', { link = 'FzfLuaSymDefault' })
  hl.set(0, 'FzfLuaHeaderText', { link = 'FzfLuaSymDefault' })
  hl.set(0, 'FzfLuaTabMarker', { link = 'Keyword' })
  hl.set(0, 'FzfLuaTabTitle', { link = 'Title' })
  hl.set(0, 'FzfLuaDirPart', { link = 'Nontext' })
  hl.set_default(0, 'TelescopeNormal', { link = 'CursorLineNr' })
  hl.set_default(0, 'TelescopeSelection', { link = 'Visual' })
  hl.set_default(0, 'TelescopePrefix', { link = 'Operator' })
  hl.set_default(0, 'TelescopeCounter', { link = 'LineNr' })
  hl.set_default(0, 'TelescopeTitle', {
    fg = hl_norm.bg,
    bg = hl_special.fg,
    ctermfg = hl_norm.ctermbg,
    ctermbg = hl_special.ctermfg,
    bold = true,
  })
end

set_default_hlgroups()

vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('FzfLuaSetDefaultHlgroups', {}),
  desc = 'Set default hlgroups for fzf-lua.',
  callback = set_default_hlgroups,
})
