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
---This fixes the bug where `switch_cwd()` does not work if it is used after
---`switch_provider()`:
---
---In `switch_provider()`, `opts.cwd` will be passed the corresponding fzf
---provider (file or grep) where it will be compiled in the command string,
---which will then be stored in `fzf.config.__resume_data.contents`.
---
---`switch_cwd()` internally calls the resume action to resume the last
---provider and reuse other info in previous fzf session (e.g. last query, etc)
---except `opts.cwd`, `opts.fn_selected`, etc. that needs to be changed to
---reflect the new cwd.
---
---Thus if `__resume_data.contents` contains information about the previous
---cwd, the new cwd in `opts.cwd` will be ignored and `switch_cwd()` will not
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

---Switch cwd while preserving the last query
---@return nil
function actions.switch_cwd()
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
    -- Append current dir '././' to the result list to allow switching to home
    -- or root directory
    -- Use '././' instead of './' to ensure that './' is shown in the result
    -- list
    -- stylua: ignore start
    cmd = string.format([[%s | sed '1i ././']],
      vim.fn.executable('fd') == 1
        and ([[fd --hidden --follow --type d --type l]]
          .. (vim.fn.executable('rg') == 1 and [[| rg /$]]
              or vim.fn.executable('grep') == 1 and [[| grep /$]]))
      or vim.fn.executable('fdfind') == 1
        and ([[fdfind --hidden --follow --type d --type l]]
          .. (vim.fn.executable('rg') == 1 and [[| rg /$]]
              or vim.fn.executable('grep') == 1 and [[| grep /$]]))
      or [[find -L * -type d -print0 | xargs -0 ls -Fd]]
    ),
    -- stylua: ignore end
    fzf_opts = { ['--no-multi'] = true },
    winopts = {
      preview = {
        hidden = 'hidden',
      },
    },
    actions = {
      ['enter'] = function(selected)
        opts.cwd = vim.fs.normalize(
          vim.fs.joinpath(
            at_home and '~' or '/',
            path.entry_to_file(selected[1]).path
          )
        )

        -- Adapted from fzf-lua `core.set_header()` function
        if opts.cwd_prompt then
          opts.prompt = vim.fn.fnamemodify(opts.cwd, ':.:~')
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
      line:match('^.+:%d+:(%w+)%s*│%s*(%S+)%s*│%s*(.-)%s*│')
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
    headers = { 'actions', 'cwd' },
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

function actions._file_edit_or_qf(selected, opts)
  if #selected > 1 then
    actions.file_sel_to_qf(selected, opts)
    vim.cmd.cfirst()
    vim.cmd.copen()
  else
    actions.file_edit(selected, opts)
  end
end

function actions._file_sel_to_qf(selected, opts)
  actions.file_sel_to_qf(selected, opts)
  if #selected > 1 then
    vim.cmd.cfirst()
    vim.cmd.copen()
  end
end

function actions._file_sel_to_ll(selected, opts)
  actions.file_sel_to_ll(selected, opts)
  if #selected > 1 then
    vim.cmd.lfirst()
    vim.cmd.lopen()
  end
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
core.ACTION_DEFINITIONS[actions.switch_cwd] = { 'Change cwd', pos = 1 }
core.ACTION_DEFINITIONS[actions.arg_del] = { 'delete' }
core.ACTION_DEFINITIONS[actions.del_autocmd] = { 'delete autocmd' }
core.ACTION_DEFINITIONS[actions.arg_search_add] = { 'add new file' }
core.ACTION_DEFINITIONS[actions.search] = { 'edit' }
core.ACTION_DEFINITIONS[actions.ex_run] = { 'edit' }

-- stylua: ignore start
config._action_to_helpstr[actions.toggle_dir] = 'toggle-dir'
config._action_to_helpstr[actions.switch_provider] = 'switch-provider'
config._action_to_helpstr[actions.switch_cwd] = 'change-cwd'
config._action_to_helpstr[actions.arg_del] = 'delete'
config._action_to_helpstr[actions.del_autocmd] = 'delete-autocmd'
config._action_to_helpstr[actions.arg_search_add] = 'search-and-add-new-file'
config._action_to_helpstr[actions.buf_sel_to_qf] = 'buffer-select-to-quickfix'
config._action_to_helpstr[actions.buf_sel_to_ll] = 'buffer-select-to-loclist'
config._action_to_helpstr[actions._file_sel_to_qf] = 'file-select-to-quickfix'
config._action_to_helpstr[actions._file_sel_to_ll] = 'file-select-to-loclist'
config._action_to_helpstr[actions._file_edit_or_qf] = 'file-edit-or-qf'
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

fzf.setup({
  -- Use nbsp in tty to avoid showing box chars
  nbsp = not vim.go.termguicolors and '\xc2\xa0' or nil,
  dir_icon = vim.trim(icons.Folder),
  winopts = {
    backdrop = 100,
    split = [[
        let tabpage_win_list = nvim_tabpage_list_wins(0) |
        \ call v:lua.require'utils.win'.saveheights(tabpage_win_list) |
        \ call v:lua.require'utils.win'.saveviews(tabpage_win_list) |
        \ unlet tabpage_win_list |
        \ let g:_fzf_vim_lines = &lines |
        \ let g:_fzf_leave_win = win_getid(winnr()) |
        \ let g:_fzf_splitkeep = &splitkeep | let &splitkeep = "topline" |
        \ let g:_fzf_cmdheight = &cmdheight | let &cmdheight = 0 |
        \ let g:_fzf_laststatus = &laststatus | let &laststatus = 0 |
        \ botright 10new |
        \ exe 'resize' .
          \ (10 + g:_fzf_cmdheight + (g:_fzf_laststatus ? 1 : 0)) |
        \ let w:winbar_no_attach = v:true |
        \ setlocal bt=nofile bh=wipe nobl noswf wfh
    ]],
    on_create = function()
      vim.keymap.set(
        't',
        '<C-r>',
        [['<C-\><C-N>"' . nr2char(getchar()) . 'pi']],
        { expr = true, buffer = true, desc = 'Insert contents in a register' }
      )
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

      if
        vim.g._fzf_leave_win
        and vim.api.nvim_win_is_valid(vim.g._fzf_leave_win)
        and vim.api.nvim_get_current_win() ~= vim.g._fzf_leave_win
      then
        vim.api.nvim_set_current_win(vim.g._fzf_leave_win)
      end
      vim.g._fzf_leave_win = nil

      if vim.go.lines == vim.g._fzf_vim_lines then
        utils.win.restheights()
      end
      vim.g._fzf_vim_lines = nil
      utils.win.clearheights()
      utils.win.restviews()
      utils.win.clearviews()
    end,
    preview = {
      hidden = 'hidden',
      layout = 'horizontal',
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
  },
  keymap = {
    -- Overrides default completion completely
    builtin = {
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
      ['alt-q'] = actions._file_sel_to_qf,
      ['alt-l'] = actions._file_sel_to_ll,
      ['enter'] = actions._file_edit_or_qf,
    },
    buffers = {
      ['enter'] = actions.buf_edit,
      ['alt-s'] = actions.buf_split,
      ['alt-v'] = actions.buf_vsplit,
      ['alt-t'] = actions.buf_tabedit,
    },
  },
  defaults = {
    headers = { 'actions' },
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
    show_unlisted = true,
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
      ['alt-e'] = actions.ex_run,
      ['ctrl-e'] = false,
    },
  },
  search_history = {
    actions = {
      ['alt-e'] = actions.search,
      ['ctrl-e'] = false,
    },
  },
  files = {
    actions = {
      ['alt-c'] = actions.switch_cwd,
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
    rg_opts = [[--color=never --files --hidden --follow -g '!.git' -g '!.venv']],
  },
  oldfiles = {
    prompt = 'Oldfiles> ',
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
    ['--no-preview'] = '',
    ['--preview-window'] = 'hidden',
  },
  grep = {
    rg_glob = true,
    actions = {
      ['alt-c'] = actions.switch_cwd,
      ['alt-h'] = actions.toggle_hidden,
      ['alt-i'] = actions.toggle_ignore,
    },
    rg_opts = table.concat({
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
    finder = {
      fzf_opts = {
        ['--info'] = 'inline-right',
      },
    },
    definitions = {
      sync = false,
      jump_to_single_result = true,
    },
    references = {
      sync = false,
      ignore_current_line = true,
      jump_to_single_result = true,
    },
    typedefs = {
      sync = false,
      jump_to_single_result = true,
    },
    symbols = {
      symbol_style = vim.g.has_nf and 1 or 3,
      symbol_icons = vim.tbl_map(vim.trim, icons.kinds),
      symbol_hl = function(sym_name)
        return 'FzfLuaSym' .. sym_name
      end,
    },
  },
})

-- stylua: ignore start
vim.keymap.set('n', '<Leader>.', fzf.files, { desc = 'Find files' })
vim.keymap.set('n', "<Leader>'", fzf.resume, { desc = 'Resume last picker' })
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
vim.keymap.set('n', '<Leader>fgc', fzf.git_commits, { desc = 'Find git commits' })
vim.keymap.set('n', '<Leader>fgl', fzf.git_bcommits, { desc = 'Find git buffer commits' })
vim.keymap.set('n', '<Leader>fgb', fzf.git_branches, { desc = 'Find git branches' })
vim.keymap.set('n', '<Leader>fgB', fzf.git_branches, { desc = 'Find git blame' })
vim.keymap.set('n', '<Leader>fh', fzf.help_tags, { desc = 'Find help tags' })
vim.keymap.set('n', '<Leader>fk', fzf.keymaps, { desc = 'Find keymaps' })
vim.keymap.set('n', '<Leader>f-', fzf.blines, { desc = 'Find lines in buffer' })
vim.keymap.set('n', '<Leader>f=', fzf.lines, { desc = 'Find lines across buffers' })
vim.keymap.set('n', '<Leader>fm', fzf.marks, { desc = 'Find marks' })
vim.keymap.set('n', '<Leader>fo', fzf.oldfiles, { desc = 'Find old files' })
vim.keymap.set('n', '<Leader>fsa', fzf.lsp_code_actions, { desc = 'Find code actions' })
vim.keymap.set('n', '<Leader>fsd', fzf.lsp_definitions, { desc = 'Find symbol definitions' })
vim.keymap.set('n', '<Leader>fsD', fzf.lsp_declarations, { desc = 'Find symbol declarations' })
vim.keymap.set('n', '<Leader>fs<C-d>', fzf.lsp_typedefs, { desc = 'Find symbol type definitions' })
vim.keymap.set('n', '<Leader>fss', fzf.lsp_document_symbols, { desc = 'Find document symbols' })
vim.keymap.set('n', '<Leader>fsS', fzf.lsp_live_workspace_symbols, { desc = 'Find workspace symbols' })
vim.keymap.set('n', '<Leader>fsi', fzf.lsp_implementations, { desc = 'Find symbol implementations' })
vim.keymap.set('n', '<Leader>fs<', fzf.lsp_incoming_calls, { desc = 'Find symbol incoming calls' })
vim.keymap.set('n', '<Leader>fs>', fzf.lsp_outgoing_calls, { desc = 'Find symbol outgoing calls' })
vim.keymap.set('n', '<Leader>fsr', fzf.lsp_references, { desc = 'Find symbol references' })
vim.keymap.set('n', '<Leader>fsR', fzf.lsp_finder, { desc = 'Find symbol locations' })
vim.keymap.set('n', '<Leader>fF', fzf.builtin, { desc = 'Find all available pickers' })
vim.keymap.set('n', '<Leader>f<Esc>', '<Nop>', { desc = 'Cancel' })
-- stylua: ignore end

---Search symbols, fallback to treesitter nodes if no language server
---supporting symbol method is attached
function fzf.symbols()
  if
    vim.tbl_isempty(vim.lsp.get_clients({
      bufnr = 0,
      method = 'textDocument/documentSymbol',
    }))
  then
    return fzf.treesitter()
  end
  return fzf.lsp_document_symbols()
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

vim.lsp.handlers['callHierarchy/incomingCalls'] = fzf.lsp_incoming_calls
vim.lsp.handlers['callHierarchy/outgoingCalls'] = fzf.lsp_outgoing_calls
vim.lsp.handlers['textDocument/codeAction'] = fzf.code_actions
vim.lsp.handlers['textDocument/declaration'] = fzf.declarations
vim.lsp.handlers['textDocument/definition'] = fzf.lsp_definitions
vim.lsp.handlers['textDocument/documentSymbol'] = fzf.lsp_document_symbols
vim.lsp.handlers['textDocument/implementation'] = fzf.lsp_implementations
vim.lsp.handlers['textDocument/references'] = fzf.lsp_references
vim.lsp.handlers['textDocument/typeDefinition'] = fzf.lsp_typedefs
vim.lsp.handlers['workspace/symbol'] = fzf.lsp_live_workspace_symbols

vim.diagnostic.setqflist = fzf.diagnostics_workspace
vim.diagnostic.setloclist = fzf.diagnostics_document

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
  hl.set_default(0, 'TelescopeSelection', { link = 'Visual' })
  hl.set_default(0, 'TelescopePrefix', { link = 'Operator' })
  hl.set_default(0, 'TelescopeCounter', { link = 'LineNr' })
  hl.set_default(0, 'TelescopeTitle', {
    fg = hl_norm.bg,
    bg = hl_special.fg,
    bold = true,
  })
end

set_default_hlgroups()

vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('FzfLuaSetDefaultHlgroups', {}),
  desc = 'Set default hlgroups for fzf-lua.',
  callback = set_default_hlgroups,
})
