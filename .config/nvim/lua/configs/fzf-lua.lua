if vim.fn.executable('fzf') == 0 then
  vim.notify('[Fzf-lua] command `fzf` not found', vim.log.levels.ERROR)
  return
end

local fzf = require('fzf-lua')
local fzf_utils = require('fzf-lua.utils')
local fzf_actions = require('fzf-lua.actions')
local fzf_core = require('fzf-lua.core')
local fzf_path = require('fzf-lua.path')
local fzf_config = require('fzf-lua.config')
local fzf_win = require('fzf-lua.win')
local fzf_builtin_previewer = require('fzf-lua.previewer.builtin')
local fzf_frecency = require('fzf-lua-frecency')
local utils = require('utils')
local icons = require('utils.static.icons')

local _arg_del = fzf_actions.arg_del
local _vimcmd_buf = fzf_actions.vimcmd_buf

---@diagnostic disable-next-line: duplicate-set-field
function fzf_actions.arg_del(...)
  pcall(_arg_del, ...)
end

---@diagnostic disable-next-line: duplicate-set-field
function fzf_actions.vimcmd_buf(...)
  pcall(_vimcmd_buf, ...)
end

---Switch provider while preserving the last query and cwd
---@return nil
function fzf_actions.switch_provider()
  local opts = {
    query = fzf.config.__resume_data.last_query,
    cwd = fzf.config.__resume_data.opts.cwd,
  }
  ---@diagnostic disable-next-line: missing-fields
  fzf.builtin({
    actions = {
      ['enter'] = function(selected)
        fzf[selected[1]](opts)
      end,
      ['esc'] = fzf_actions.resume,
    },
  })
end

---Change cwd while preserving the last query
---@return nil
function fzf_actions.change_cwd()
  local resume_data = vim.tbl_deep_extend('force', fzf.config.__resume_data, {
    opts = {},
  })
  local opts = resume_data.opts

  local cwd = opts.cwd or vim.fn.getcwd(0)
  local cwd_in_home = utils.fs.contains('~', cwd)
  local cwd_root = cwd_in_home and '~/' or '/'

  fzf.files({
    cwd_prompt = false,
    prompt = 'New cwd: ' .. cwd_root,
    cwd = cwd_root,
    query = vim.fn
      .fnamemodify(cwd, cwd_in_home and ':~' or ':p')
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
      -- Open the same picker with selected new cwd but keep old query
      ['enter'] = function(selected)
        if not selected[1] then
          return
        end

        -- Remove old fn_selected, else selected item will be opened
        -- with previous cwd
        opts.fn_selected = nil
        opts.resume = true
        opts.query = resume_data.last_query
        opts.cwd = vim.fs.normalize(
          vim.fs.joinpath(
            cwd_root,
            fzf_path.entry_to_file(selected[1], {}, false).path
          )
        )

        -- Adapted from fzf-lua `core.set_header()` function
        if opts.cwd_prompt then
          opts.prompt = vim.fn.fnamemodify(opts.cwd, ':~')
          local shorten_len = tonumber(opts.cwd_prompt_shorten_len)
          if shorten_len and #opts.prompt >= shorten_len then
            opts.prompt = fzf_path.shorten(
              opts.prompt,
              tonumber(opts.cwd_prompt_shorten_val) or 1
            )
          end
          if not fzf_path.ends_with_separator(opts.prompt) then
            opts.prompt = opts.prompt .. fzf_path.separator()
          end
        end
        if opts.headers then
          opts = fzf_core.set_header(opts)
        end

        -- Get old picker from `opts.__resume_key`, fallback to files picker
        (fzf[opts.__resume_key] or fzf.files)(opts)
      end,
      ['esc'] = function()
        fzf.config.__resume_data = resume_data
        fzf_actions.resume()
      end,
      -- Should not change dir or exclude dirs when selecting cwd
      ['alt-c'] = false,
      ['alt-/'] = false,
    },
  })
end

---Include directories, not only files when using the `files` picker
---@return nil
function fzf_actions.toggle_dir(_, opts)
  local flag ---@type string?
  local flag_cmd_idx ---@type integer?
  local cmds = vim.iter(opts.cmd:gmatch('([^|;&]+[|;&]*)')):totable()

  -- Handle multiple cmds in one string, e.g. fzf-lua-frecency uses two
  -- commands in a row: 'cat ... ; fd ...'
  --
  -- fzf-lua-frecency does not support overriding cmd passed in `opts` yet
  -- TODO: make a PR for it
  for i, cmd in ipairs(cmds) do
    local exec = cmd:match('^%s*(%S+)')
    if exec == 'fd' or exec == 'fdfind' then
      flag = '--type d'
      flag_cmd_idx = i
      break
    end
    if exec == 'find' then
      flag = '-type d'
      flag_cmd_idx = i
      break
    end
  end
  if not flag or not flag_cmd_idx then
    return
  end

  cmds[flag_cmd_idx] = fzf_utils.toggle_cmd_flag(cmds[flag_cmd_idx], flag)

  opts.__call_fn(vim.tbl_deep_extend('force', opts.__call_opts, {
    cmd = table.concat(cmds),
    resume = true,
  }))
end

---Delete selected autocmd
---@return nil
function fzf_actions.del_autocmd(selected)
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
function fzf_actions.arg_search_add()
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
        fzf_actions.vimcmd_file(cmd, selected, o)
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

local _file_split = fzf_actions.file_split
local _file_vsplit = fzf_actions.file_vsplit
local _file_tabedit = fzf_actions.file_tabedit
local _file_sel_to_qf = fzf_actions.file_sel_to_qf
local _file_sel_to_ll = fzf_actions.file_sel_to_ll
local _buf_split = fzf_actions.buf_split
local _buf_vsplit = fzf_actions.buf_vsplit
local _buf_tabedit = fzf_actions.buf_tabedit

---@diagnostic disable-next-line: duplicate-set-field
function fzf_actions.file_split(...)
  local win = vim.api.nvim_get_current_win()
  _file_split(...)
  if vim.api.nvim_win_is_valid(win) and utils.win.is_empty(win) then
    vim.api.nvim_win_close(win, false)
  end
end

---@diagnostic disable-next-line: duplicate-set-field
function fzf_actions.file_vsplit(...)
  local win = vim.api.nvim_get_current_win()
  _file_vsplit(...)
  if vim.api.nvim_win_is_valid(win) and utils.win.is_empty(win) then
    vim.api.nvim_win_close(win, false)
  end
end

---@diagnostic disable-next-line: duplicate-set-field
function fzf_actions.file_tabedit(...)
  local tab = vim.api.nvim_get_current_tabpage()
  _file_tabedit(...)
  if vim.api.nvim_tabpage_is_valid(tab) and utils.tab.is_empty(tab) then
    vim.api.nvim_win_close(vim.api.nvim_tabpage_list_wins(tab)[1], false)
  end
end

---@diagnostic disable-next-line: duplicate-set-field
function fzf_actions.file_edit_or_qf(selected, opts)
  if #selected > 1 then
    fzf_actions.file_sel_to_qf(selected, opts)
    vim.cmd.cfirst()
    vim.cmd.copen()
  else
    -- Fix oil buffer concealing issue when opening some dirs
    vim.schedule(function()
      fzf_actions.file_edit(selected, opts)
    end)
  end
end

---@diagnostic disable-next-line: duplicate-set-field
function fzf_actions.file_sel_to_qf(selected, opts)
  _file_sel_to_qf(selected, opts)
  if #selected > 1 then
    vim.cmd.cfirst()
    vim.cmd.copen()
  end
end

---@diagnostic disable-next-line: duplicate-set-field
function fzf_actions.file_sel_to_ll(selected, opts)
  _file_sel_to_ll(selected, opts)
  if #selected > 1 then
    vim.cmd.lfirst()
    vim.cmd.lopen()
  end
end

---@diagnostic disable-next-line: duplicate-set-field
function fzf_actions.buf_split(...)
  local win = vim.api.nvim_get_current_win()
  _buf_split(...)
  if vim.api.nvim_win_is_valid(win) and utils.win.is_empty(win) then
    vim.api.nvim_win_close(win, false)
  end
end

---@diagnostic disable-next-line: duplicate-set-field
function fzf_actions.buf_vsplit(...)
  local win = vim.api.nvim_get_current_win()
  _buf_vsplit(...)
  if vim.api.nvim_win_is_valid(win) and utils.win.is_empty(win) then
    vim.api.nvim_win_close(win, false)
  end
end

---@diagnostic disable-next-line: duplicate-set-field
function fzf_actions.buf_tabedit(...)
  local tab = vim.api.nvim_get_current_tabpage()
  _buf_tabedit(...)
  if vim.api.nvim_tabpage_is_valid(tab) and utils.tab.is_empty(tab) then
    vim.api.nvim_win_close(vim.api.nvim_tabpage_list_wins(tab)[1], false)
  end
end

function fzf_actions.insert_register(...)
  fzf_actions.paste_register(...)
  vim.api.nvim_feedkeys('a', 'n', true)
end

---Check if fugitive `:Gedit` command exists
---@param notify? boolean whether to notify user when command does not exist
---@return boolean
local function has_fugitive_gedit_cmd(notify)
  if vim.fn.exists(':Gedit') == 2 then
    return true
  end
  if notify then
    vim.notify(
      '[Fzf-lua] command `:Gedit` does not exist',
      vim.log.levels.WARN
    )
  end
  return false
end

---Edit a git commit object with vim-fugitive
function fzf_actions.fugitive_edit(selected)
  if not has_fugitive_gedit_cmd(true) or not selected[1] then
    return
  end
  vim.cmd.Gedit(selected[1]:match('^%x+'))
end

---Edit a git commit object in horizontal split with vim-fugitive
function fzf_actions.fugitive_split(selected)
  if not has_fugitive_gedit_cmd(true) then
    return
  end
  vim.cmd.split()
  fzf_actions.fugitive_edit(selected)
end

---Edit a git commit object in vertical split with vim-fugitive
function fzf_actions.fugitive_vsplit(selected)
  if not has_fugitive_gedit_cmd(true) then
    return
  end
  vim.cmd.vsplit()
  fzf_actions.fugitive_edit(selected)
end

---Edit a git commit object in vertical split with vim-fugitive
function fzf_actions.fugitive_tabedit(selected)
  if not has_fugitive_gedit_cmd(true) then
    return
  end
  vim.cmd.tabnew()
  fzf_actions.fugitive_edit(selected)
end

fzf_core.ACTION_DEFINITIONS[fzf_actions.toggle_dir] = {
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

fzf_core.ACTION_DEFINITIONS[fzf_actions.toggle_dir] = {
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
-- stylua: ignore start
fzf_core.ACTION_DEFINITIONS[fzf_actions.change_cwd] = { 'Change cwd', pos = 1 }
fzf_core.ACTION_DEFINITIONS[fzf_actions.arg_del] = { 'delete' }
fzf_core.ACTION_DEFINITIONS[fzf_actions.del_autocmd] = { 'delete autocmd' }
fzf_core.ACTION_DEFINITIONS[fzf_actions.arg_search_add] = { 'add new file' }
fzf_core.ACTION_DEFINITIONS[fzf_actions.search] = { 'edit' }
fzf_core.ACTION_DEFINITIONS[fzf_actions.ex_run] = { 'edit' }
fzf_core.ACTION_DEFINITIONS[fzf_actions.insert_register] = { 'insert register' }
-- stylua: ignore end

-- stylua: ignore start
fzf_config._action_to_helpstr[fzf_actions.toggle_dir] = 'toggle-dir'
fzf_config._action_to_helpstr[fzf_actions.switch_provider] = 'switch-provider'
fzf_config._action_to_helpstr[fzf_actions.change_cwd] = 'change-cwd'
fzf_config._action_to_helpstr[fzf_actions.arg_del] = 'delete'
fzf_config._action_to_helpstr[fzf_actions.del_autocmd] = 'delete-autocmd'
fzf_config._action_to_helpstr[fzf_actions.arg_search_add] = 'search-and-add-new-file'
fzf_config._action_to_helpstr[fzf_actions.file_split] = 'file-split'
fzf_config._action_to_helpstr[fzf_actions.file_vsplit] = 'file-vsplit'
fzf_config._action_to_helpstr[fzf_actions.file_tabedit] = 'file-tabedit'
fzf_config._action_to_helpstr[fzf_actions.file_edit_or_qf] = 'file-edit-or-qf'
fzf_config._action_to_helpstr[fzf_actions.file_sel_to_qf] = 'file-select-to-quickfix'
fzf_config._action_to_helpstr[fzf_actions.file_sel_to_ll] = 'file-select-to-loclist'
fzf_config._action_to_helpstr[fzf_actions.buf_split] = 'buffer-split'
fzf_config._action_to_helpstr[fzf_actions.buf_vsplit] = 'buffer-vsplit'
fzf_config._action_to_helpstr[fzf_actions.buf_tabedit] = 'buffer-tabedit'
fzf_config._action_to_helpstr[fzf_actions.buf_edit_or_qf] = 'buffer-edit-or-qf'
fzf_config._action_to_helpstr[fzf_actions.buf_sel_to_qf] = 'buffer-select-to-quickfix'
fzf_config._action_to_helpstr[fzf_actions.buf_sel_to_ll] = 'buffer-select-to-loclist'
fzf_config._action_to_helpstr[fzf_actions.insert_register] = 'insert-register'
fzf_config._action_to_helpstr[fzf_actions.fugitive_edit] = 'fugitive-edit'
fzf_config._action_to_helpstr[fzf_actions.fugitive_split] = 'fugitive-split'
fzf_config._action_to_helpstr[fzf_actions.fugitive_vsplit] = 'fugitive-vsplit'
fzf_config._action_to_helpstr[fzf_actions.fugitive_tabedit] = 'fugitive-tabedit'
-- stylua: ignore end

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
      method = vim.lsp.protocol.Methods.textDocument_documentSymbol,
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

---@param opts table?
function fzf.files_with_frecency(opts)
  return fzf_frecency.frecency(vim.tbl_deep_extend('keep', opts, {
    cwd_prompt = true,
    cwd_only = true,
    cwd = opts and opts.cwd or vim.fn.getcwd(0),
  }))
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
  fzf_actions.z = z.jump
  fzf_core.ACTION_DEFINITIONS[fzf_actions.z] = { 'jump to dir' }
  fzf_config._action_to_helpstr[fzf_actions.z] = 'jump-to-dir'

  return fzf.fzf_exec(
    z.list(),
    vim.tbl_deep_extend('force', opts or {}, {
      cwd = vim.fn.getcwd(0),
      prompt = 'Open directory: ',
      actions = {
        ['enter'] = fzf_actions.z,
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
  fzf_actions.load_session = action(function(p)
    session.load(p, true)
  end)
  fzf_core.ACTION_DEFINITIONS[fzf_actions.load_session] = { 'load session' }
  fzf_config._action_to_helpstr[fzf_actions.load_session] = 'load-session'

  fzf_actions.remove_session = action(session.remove)
  fzf_core.ACTION_DEFINITIONS[fzf_actions.remove_session] =
    { 'remove session' }
  fzf_config._action_to_helpstr[fzf_actions.remove_session] = 'remove-session'

  return fzf.fzf_exec(
    string.format(
      [[ls -1 %s | while read -r file; do echo "$file" | sed 's/%%/\//g' | sed 's/\/\//%%/g'; done]],
      session.opts.dir
    ),
    vim.tbl_deep_extend('force', opts or {}, {
      prompt = 'Sessions: ',
      actions = {
        ['enter'] = fzf_actions.load_session,
        ['ctrl-x'] = {
          fn = fzf_actions.remove_session,
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
      ['enter'] = fzf_actions.insert_register,
    },
  }))
end

-- HACK: override fzf internals to reuse source window as preview window
local _win_generate_layout = fzf_win.generate_layout
local _win_redraw_preview = fzf_win.redraw_preview
local _win_close_preview = fzf_win.close_preview
local _builtin_previewer_preview_window =
  fzf_builtin_previewer.base.preview_window

---Hide but don't disable fzf native preview when using split layout, so that
---we can sync builtin previewer with fzf
function fzf_builtin_previewer.base:preview_window(...)
  return self.win and self.win.winopts.split and 'nohidden:right:0'
    or _builtin_previewer_preview_window(self, ...)
end

---@diagnostic disable-next-line: inject-field
function fzf_builtin_previewer.base:backup_winhl()
  self.winopts_orig = self.winopts_orig or {} -- fix nil error
  ---@diagnostic disable-next-line: inject-field
  if self.win.src_winid and vim.api.nvim_win_is_valid(self.win.src_winid) then
    self.winhl_orig = vim.wo[self.win.src_winid].winhl
  end
end

---@diagnostic disable-next-line: inject-field
function fzf_builtin_previewer.base:restore_winhl()
  if
    self.winhl_orig
    and self.win.src_winid
    and vim.api.nvim_win_is_valid(self.win.src_winid)
  then
    vim.wo[self.win.src_winid].winhl = self.winhl_orig
  end
end

function fzf_win:generate_layout(...)
  -- Handle split preview if fzf main window is a split window
  if self.winopts.split then
    self.layout = {
      fzf = self:normalize_border({
        row = self.winopts.row,
        col = self.winopts.col,
        width = self.winopts.width,
        height = self.winopts.height,
        border = self._o.winopts.border,
        relative = self.winopts.relative or 'editor',
        zindex = self.winopts.zindex,
        hide = self.winopts.hide,
      }, { type = 'nvim', name = 'fzf', nwin = 2 }),
      preview = {
        border = self._o.winopts.preview.border,
        focusable = true,
        hide = self.winopts.hide,
      },
    }
    return
  end
  _win_generate_layout(self, ...)
end

function fzf_win:redraw_preview(...)
  -- Reuse source win or create a new split window for preview
  if self.winopts.split and not self:validate_preview() then
    if self.src_winid and vim.fn.win_gettype(self.src_winid) == '' then
      self.preview_winid = self.src_winid
    else
      -- Use first 'normal' window as source & preview window
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.fn.win_gettype(win) == '' then
          self.preview_winid = win
          self.src_winid = win
          self.src_bufnr = vim.api.nvim_win_get_buf(win)
          break
        end
      end
      -- No existing normal window, create a new window for the previewer
      if not self.preview_winid then
        self.preview_winid = vim.api.nvim_open_win(0, false, {
          split = 'above',
          win = 0,
        })
      end
    end
    if not self.preview_winid then
      return
    end

    -- Record source buffer name for some special temporary buffers, e.g.
    -- `fugitive://` or `oil://` buffers so that we can restore them by
    -- editing files with the same name if they are deleted after hidden
    --
    -- This has a drawback that the cursor position in the original buffer will
    -- not be restored because original buffer has lost
    if self.src_bufnr and vim.api.nvim_buf_is_valid(self.src_bufnr) then
      ---@diagnostic disable-next-line: inject-field
      self.src_bufname = vim.api.nvim_buf_get_name(self.src_bufnr)
    end

    if self._previewer then
      -- Only builtin previewers have additional backup/restore methods
      ---@diagnostic disable: undefined-field
      if self._previewer.backup_winhl then
        self._previewer:backup_winhl()
      end
      if self._previewer.backup_winopts then
        self._previewer:backup_winopts()
      end
      ---@diagnostic enable: undefined-field
      ---@diagnostic disable-next-line: inject-field
      self._previewer_winopts_orig = self._previewer.winopts_orig
    end
  end
  ---@diagnostic disable-next-line: redundant-parameter
  return _win_redraw_preview(self, ...)
end

function fzf_win:close_preview(...)
  if
    not self.preview_winid or not vim.api.nvim_win_is_valid(self.preview_winid)
  then
    return
  end

  -- For normal floating window preview with a separate preview window, just
  -- use the original `close_preview` method
  if self.preview_winid ~= self.src_winid then
    return _win_close_preview(self, ...)
  end

  -- For split preview windows that reuse source window, set buffer back to
  -- source buffer instead of closing the window, fallback to new buffer with
  -- the same name if the original source buffer is invalid or unavailable
  local buf = self.src_bufnr
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    buf = vim.api.nvim_create_buf(true, false)
    -- Try restoring deleted temp buffers
    if self.src_bufname then
      vim.api.nvim_buf_set_name(buf, self.src_bufname)
      vim.api.nvim_buf_call(buf, vim.cmd.edit)
    end
  end
  vim.api.nvim_win_set_buf(self.preview_winid, buf)

  -- Prevent original `_win_close_preview` from closing the preview & source
  -- window
  self.preview_winid = nil
  _win_close_preview(self, ...)

  -- Restore preview window id, `self._previewer:restore_winopts()` needs this
  self.preview_winid = self.src_winid

  -- Restore source window appearance
  vim.schedule(vim.schedule_wrap(function()
    if self._previewer then
      ---@diagnostic disable: undefined-field
      if self._previewer.restore_winhl then
        self._previewer:restore_winhl()
      end
      ---@diagnostic enable: undefined-field

      if self._previewer.restore_winopts then
        self._previewer.winopts_orig = self._previewer_winopts_orig or {}
        self._previewer:restore_winopts()
      end
    end
  end))
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
        \   let g:_fzf_qfheight = nvim_win_get_height(win_getid(winnr('$'))) |
        \   let g:_fzf_height = g:_fzf_qfheight - 1 |
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

      if vim.go.lines == vim.g._fzf_vim_lines then
        utils.win.restore_heights(_G._fzf_lua_win_heights)
      end
      vim.g._fzf_vim_lines = nil
      _G._fzf_lua_win_heights = {}

      utils.win.restore_views(_G._fzf_lua_win_views)
      _G._fzf_lua_win_views = {}

      -- Reopen quickfix/location list after closing fzf if we previous closed
      -- it to make space for fzf
      --
      -- Schedule in case the fzf is making a new split
      -- (e.g. `actions.file_split`) after opening quickfix window which
      -- resizes the quickfix window unexpectedly due to an nvim bug, see
      -- - `lua/core/autocmds.lua` augroup `FixWinFixHeightWithWinBar`
      -- -  https://github.com/neovim/neovim/issues/30955
      vim.schedule(function()
        local win = vim.api.nvim_get_current_win()

        if vim.g._fzf_qfclosed == 'loclist' then
          vim.cmd.lopen({
            count = vim.g._fzf_qfheight,
          })
        elseif vim.g._fzf_qfclosed == 'quickfix' then
          vim.cmd.copen({
            count = vim.g._fzf_qfheight,
          })
        end
        vim.g._fzf_qfclosed = nil
        vim.g._fzf_qfheight = nil

        -- Keep window visit order
        if
          vim.g._fzf_leave_win
          and vim.api.nvim_win_is_valid(vim.g._fzf_leave_win)
        then
          vim.api.nvim_set_current_win(vim.g._fzf_leave_win)
        end
        vim.g._fzf_leave_win = nil

        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_set_current_win(win)
        end
      end)
    end,
    preview = {
      border = 'solid',
      layout = 'horizontal',
      scrollbar = false,
      winopts = {
        colorcolumn = '',
        signcolumn = vim.go.signcolumn,
        statuscolumn = vim.go.statuscolumn,
        cursorlineopt = vim.go.cursorlineopt,
      },
    },
  },
  -- Open help window at top of screen with single border
  help_open_win = function(buf, enter, opts)
    opts.border = 'single'
    opts.row = 0
    opts.col = 0
    return vim.api.nvim_open_win(buf, enter, opts)
  end,
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
      ['alt-s'] = fzf_actions.file_split,
      ['alt-v'] = fzf_actions.file_vsplit,
      ['alt-t'] = fzf_actions.file_tabedit,
      ['alt-q'] = fzf_actions.file_sel_to_qf,
      ['alt-l'] = fzf_actions.file_sel_to_ll,
      ['enter'] = fzf_actions.file_edit_or_qf,
    },
    buffers = {
      ['alt-s'] = fzf_actions.buf_split,
      ['alt-v'] = fzf_actions.buf_vsplit,
      ['alt-t'] = fzf_actions.buf_tabedit,
      ['enter'] = fzf_actions.buf_edit_or_qf,
    },
  },
  defaults = {
    actions = {
      ['ctrl-]'] = fzf_actions.switch_provider,
    },
  },
  args = {
    files_only = false,
    actions = {
      ['ctrl-s'] = fzf_actions.arg_search_add,
      ['ctrl-x'] = {
        fn = fzf_actions.arg_del,
        reload = true,
      },
    },
  },
  autocmds = {
    actions = {
      ['ctrl-x'] = {
        fn = fzf_actions.del_autocmd,
        -- reload = true,
      },
    },
  },
  blines = {
    actions = {
      ['alt-q'] = fzf_actions.buf_sel_to_qf,
      ['alt-l'] = fzf_actions.buf_sel_to_ll,
    },
  },
  lines = {
    actions = {
      ['alt-q'] = fzf_actions.buf_sel_to_qf,
      ['alt-l'] = fzf_actions.buf_sel_to_ll,
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
      ['enter'] = fzf_actions.help,
      ['alt-s'] = fzf_actions.help,
      ['alt-v'] = fzf_actions.help_vert,
      ['alt-t'] = fzf_actions.help_tab,
    },
  },
  manpages = {
    actions = {
      ['enter'] = fzf_actions.man,
      ['alt-s'] = fzf_actions.man,
      ['alt-v'] = fzf_actions.man_vert,
      ['alt-t'] = fzf_actions.man_tab,
    },
  },
  keymaps = {
    actions = {
      ['enter'] = fzf_actions.keymap_edit,
      ['alt-s'] = fzf_actions.keymap_split,
      ['alt-v'] = fzf_actions.keymap_vsplit,
      ['alt-t'] = fzf_actions.keymap_tabedit,
    },
  },
  colorschemes = {
    actions = {
      ['enter'] = fzf_actions.colorscheme,
    },
  },
  command_history = {
    actions = {
      ['enter'] = fzf_actions.ex_run,
      ['ctrl-e'] = false,
    },
  },
  search_history = {
    actions = {
      ['enter'] = fzf_actions.search,
      ['ctrl-e'] = false,
    },
  },
  files = {
    actions = {
      ['alt-c'] = fzf_actions.change_cwd,
      ['alt-h'] = fzf_actions.toggle_hidden,
      ['alt-i'] = fzf_actions.toggle_ignore,
      ['alt-/'] = fzf_actions.toggle_dir,
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
      actions = has_fugitive_gedit_cmd() and {
        ['enter'] = fzf_actions.fugitive_edit,
        ['alt-s'] = fzf_actions.fugitive_split,
        ['alt-v'] = fzf_actions.fugitive_vsplit,
        ['alt-t'] = fzf_actions.fugitive_tabedit,
        ['ctrl-y'] = {
          fn = fzf_actions.git_yank_commit,
          exec_silent = true,
        },
      } or nil,
    },
    bcommits = {
      prompt = 'GitLogs>',
      actions = has_fugitive_gedit_cmd() and {
        ['enter'] = fzf_actions.fugitive_edit,
        ['alt-s'] = fzf_actions.fugitive_split,
        ['alt-v'] = fzf_actions.fugitive_vsplit,
        ['alt-t'] = fzf_actions.fugitive_tabedit,
        ['ctrl-y'] = {
          fn = fzf_actions.git_yank_commit,
          exec_silent = true,
        },
      } or nil,
    },
    blame = {
      actions = {
        ['enter'] = fzf_actions.git_goto_line,
        ['alt-s'] = fzf_actions.git_buf_split,
        ['alt-v'] = fzf_actions.git_buf_vsplit,
        ['alt-t'] = fzf_actions.git_buf_tabedit,
        ['ctrl-y'] = { fn = fzf_actions.git_yank_commit, exec_silent = true },
      },
    },
    branches = {
      actions = {
        ['ctrl-s'] = {
          fn = fzf_actions.git_branch_add,
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
    -- Respect global ripgrep config, see
    -- - https://github.com/ibhagwan/fzf-lua/issues/2187
    -- - https://github.com/ibhagwan/fzf-lua/issues/1506#issuecomment-2447299360
    RIPGREP_CONFIG_PATH = vim.env.RIPGREP_CONFIG_PATH,
    rg_glob = true,
    actions = {
      ['alt-c'] = fzf_actions.change_cwd,
      ['alt-h'] = fzf_actions.toggle_hidden,
      ['alt-i'] = fzf_actions.toggle_ignore,
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

---@diagnostic disable-next-line: missing-fields
fzf_frecency.setup({
  display_score = false,
  actions = fzf_config.setup_opts.files.actions,
})

-- stylua: ignore start
vim.keymap.set('c', '<C-_>', fzf.complete_cmdline, { desc = 'Fuzzy complete command/search history' })
vim.keymap.set('c', '<C-x><C-l>', fzf.complete_cmdline, { desc = 'Fuzzy complete command/search history' })
vim.keymap.set('i', '<C-r>?', fzf.complete_from_registers, { desc = 'Fuzzy complete from registers' })
vim.keymap.set('i', '<C-r><C-_>', fzf.complete_from_registers, { desc = 'Fuzzy complete from registers' })
vim.keymap.set('i', '<C-r><C-r>', fzf.complete_from_registers, { desc = 'Fuzzy complete from registers' })
vim.keymap.set('i', '<C-x><C-f>', fzf.complete_path, { desc = 'Fuzzy complete path' })
vim.keymap.set('n', '<Leader>.', fzf.files_with_frecency, { desc = 'Find files' })
vim.keymap.set('n', "<Leader>'", fzf.resume, { desc = 'Resume last picker' })
vim.keymap.set('n', "<Leader>`", fzf.marks, { desc = 'Find marks' })
vim.keymap.set('n', '<Leader>,', fzf.buffers, { desc = 'Find buffers' })
vim.keymap.set('n', '<Leader>%', fzf.tabs, { desc = 'Find tabpages' })
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
vim.keymap.set('n', '<Leader>ff', fzf.files_with_frecency, { desc = 'Find files' })
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
