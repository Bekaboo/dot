vim.g.has_ui = #vim.api.nvim_list_uis() > 0
vim.g.has_gui = vim.fn.has('gui_running') == 1
vim.g.has_display = vim.g.has_ui and vim.env.DISPLAY ~= nil
vim.g.has_nf = vim.env.TERM ~= 'linux' and vim.env.NVIM_NF and true or false

vim.opt.exrc = true
vim.opt.confirm = true
vim.opt.timeout = false
vim.opt.colorcolumn = '+1'
vim.opt.cursorlineopt = 'number'
vim.opt.cursorline = true
vim.opt.helpheight = 10
vim.opt.showmode = false
vim.opt.mousemoveevent = true
vim.opt.number = true
vim.opt.ruler = true
vim.opt.pumheight = 16
vim.opt.scrolloff = 4
vim.opt.sidescrolloff = 8
vim.opt.signcolumn = 'yes:1'
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.swapfile = false
vim.opt.undofile = true
vim.opt.wrap = false
vim.opt.linebreak = true
vim.opt.breakindent = true
vim.opt.smoothscroll = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.completeopt = 'menuone'
vim.opt.jumpoptions = 'stack,view'
vim.opt.selection = 'old'
vim.opt.tabclose = 'uselast'

-- Defer shada reading
local shada_augroup = vim.api.nvim_create_augroup('OptShada', {})

---Restore 'shada' option and read from shada once
local function rshada()
  pcall(vim.api.nvim_del_augroup_by_id, shada_augroup)

  vim.opt.shada = vim.api.nvim_get_option_info2('shada', {}).default
  pcall(vim.cmd.rshada)
end

vim.opt.shada = ''
vim.api.nvim_create_autocmd('BufReadPre', {
  group = shada_augroup,
  once = true,
  callback = rshada,
})
vim.api.nvim_create_autocmd('UIEnter', {
  group = shada_augroup,
  once = true,
  callback = vim.schedule_wrap(rshada),
})

-- Folding
vim.opt.foldlevelstart = 99
vim.opt.foldtext = ''
vim.opt.foldmethod = 'indent'

-- Enable treesitter folding
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('TSFolding', {}),
  desc = 'Set treesitter folding.',
  callback = function(info)
    local buf = info.buf
    if not require('utils.ts').is_active(buf) then
      return
    end

    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      local wo = vim.wo[win]
      if wo.foldexpr == '0' then
        wo[0].foldexpr = 'v:lua.vim.treesitter.foldexpr()'
        if wo.foldmethod == 'indent' or wo.foldmethod == 'manual' then
          wo[0].foldmethod = 'expr'
        end
      end
    end
  end,
})

-- Enable LSP folding
vim.api.nvim_create_autocmd({ 'LspAttach', 'LspDetach' }, {
  desc = 'Set LSP folding.',
  group = vim.api.nvim_create_augroup('LSPFolding', {}),
  callback = function(info)
    local id = info.data and info.data.client_id
    if not id then
      return
    end

    local lsp_foldmethod = 'textDocument/foldingRange'
    local client = vim.lsp.get_client_by_id(id)
    if not client or not client:supports_method(lsp_foldmethod) then
      return
    end

    local lsp_foldexpr = 'v:lua.vim.lsp.foldexpr()'
    local ts_foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    if info.event == 'LspAttach' then
      for buf, _ in pairs(client.attached_buffers) do
        for _, win in ipairs(vim.fn.win_findbuf(buf)) do
          local wo = vim.wo[win]
          if wo.foldexpr == '0' or wo.foldexpr == ts_foldexpr then
            wo[0].foldexpr = lsp_foldexpr
            if wo.foldmethod == 'indent' or wo.foldmethod == 'manual' then
              wo[0].foldmethod = 'expr'
            end
          end
        end
      end
    else -- event == 'LspDetach'
      local buf = info.buf
      -- Clients attached to `buf` that supports folding method
      local clients = vim
        .iter(vim.lsp.get_clients({ bufnr = buf }))
        :filter(function(c)
          return c:supports_method(lsp_foldmethod)
        end)
      -- `buf` still has clients that supports folding methods attached to it,
      -- don't fallback to treesitter folding
      -- Skip 1 client because current client has not been detached from `buf`
      -- yet
      if clients:skip(1):peek() then
        return
      end
      for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        local wo = vim.wo[win]
        if wo.foldexpr == lsp_foldexpr then
          if require('utils.ts').is_active(buf) then
            wo[0].foldexpr = ts_foldexpr
          else
            wo[0].foldmethod = 'indent'
          end
        end
      end
    end
  end,
})

-- Recognize numbered lists when formatting text and
-- continue comments on new lines
vim.opt.formatoptions:append('norm')

-- Spell check
vim.opt.spellsuggest = 'best,9'
vim.opt.spellcapcheck = ''
vim.opt.spelllang = 'en,cjk'
vim.opt.spelloptions = 'camel'

local spell_augroup = vim.api.nvim_create_augroup('OptSpell', {})

---Set spell check options
---@return nil
local function spellcheck()
  pcall(vim.api.nvim_del_augroup_by_id, spell_augroup)

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if not require('utils.opt').spell:was_locally_set({ win = win }) then
      vim.wo[win][0].spell = true
    end
  end
end

vim.api.nvim_create_autocmd('FileType', {
  group = spell_augroup,
  once = true,
  callback = function()
    local ts_start = vim.treesitter.start
    function vim.treesitter.start(...) ---@diagnostic disable-line: duplicate-set-field
      -- Ensure spell check settings are set before starting treesitter
      -- to avoid highlighting `@nospell` nodes
      spellcheck()
      vim.treesitter.start = ts_start
      return vim.treesitter.start(...)
    end
  end,
})

vim.api.nvim_create_autocmd('UIEnter', {
  group = spell_augroup,
  once = true,
  callback = vim.schedule_wrap(spellcheck),
})

-- Cursor shape
vim.opt.gcr = {
  'i-c-ci-ve:blinkoff500-blinkon500-block-TermCursor',
  'n-v:block-Curosr/lCursor',
  'o:hor50-Curosr/lCursor',
  'r-cr:hor20-Curosr/lCursor',
}

-- Use histogram algorithm for diffing, generates more readable diffs in
-- situations where two lines are swapped
vim.opt.diffopt:append({
  'algorithm:histogram',
  'indent-heuristic',
  'linematch:60',
})

-- Use system clipboard
vim.api.nvim_create_autocmd('UIEnter', {
  once = true,
  callback = vim.schedule_wrap(function()
    vim.opt.clipboard:append('unnamedplus')
  end),
})

-- Align columns in quickfix window
vim.opt.quickfixtextfunc = [[v:lua.require'utils.misc'.qftf]]

vim.opt.backup = true
vim.opt.backupdir:remove('.')

vim.opt.list = true
vim.opt.listchars = {
  tab = '  ',
  trail = '·',
}
vim.opt.fillchars = {
  fold = '·',
  foldsep = ' ',
  eob = ' ',
}

if vim.g.has_nf then
  vim.opt.fillchars:append({
    foldopen = '',
    foldclose = '',
  })
end

vim.api.nvim_create_autocmd('UIEnter', {
  once = true,
  callback = function()
    if vim.opt.termguicolors:get() then
      vim.opt.listchars:append({ nbsp = '␣' })
      vim.opt.fillchars:append({ diff = '╱' })
    end
  end,
})

-- Netrw settings
vim.g.netrw_banner = 0
vim.g.netrw_cursor = 5
vim.g.netrw_keepdir = 0
vim.g.netrw_keepj = ''
vim.g.netrw_list_hide = [[\(^\|\s\s\)\zs\.\S\+]]
vim.g.netrw_liststyle = 1
vim.g.netrw_localcopydircmd = 'cp -r'

-- Fzf settings
vim.g.fzf_layout = {
  window = {
    width = 0.8,
    height = 0.8,
    pos = 'center',
  },
}
vim.env.FZF_DEFAULT_OPTS = (vim.env.FZF_DEFAULT_OPTS or '')
  .. ' --border=sharp --margin=0 --padding=0'

-- Disable plugins shipped with nvim
vim.g.loaded_2html_plugin = 0
vim.g.loaded_gzip = 0
vim.g.loaded_matchit = 0
vim.g.loaded_spellfile_plugin = 0
vim.g.loaded_tar = 0
vim.g.loaded_tarPlugin = 0
vim.g.loaded_tutor_mode_plugin = 0
vim.g.loaded_zip = 0
vim.g.loaded_zipPlugin = 0

---Lazy-load runtime files
---@param runtime string
---@param flag string
---@param events string|string[]
local function load(runtime, flag, events)
  if vim.g[flag] and vim.g[flag] ~= 0 then
    return
  end

  vim.g[flag] = 0
  if type(events) ~= 'table' then
    events = { events }
  end

  local gid = vim.api.nvim_create_augroup('Load_' .. runtime, {})
  for _, e in
    ipairs(vim.tbl_map(function(e)
      return vim.split(e, ' ', {
        trimempty = true,
        plain = true,
      })
    end, events))
  do
    vim.api.nvim_create_autocmd(e[1], {
      once = true,
      pattern = e[2],
      group = gid,
      callback = function()
        if vim.g[flag] == 0 then
          vim.g[flag] = nil
          vim.cmd.runtime(runtime)
        end
        vim.api.nvim_del_augroup_by_id(gid)
      end,
    })
  end
end

load('plugin/rplugin.vim', 'loaded_remote_plugins', {
  'FileType',
  'BufNew',
  'BufWritePost',
  'BufReadPre',
})
load('provider/python3.vim', 'loaded_python3_provider', {
  'FileType python',
  'BufNew *.py,*.ipynb',
  'BufEnter *.py,*.ipynb',
  'BufWritePost *.py,*.ipynb',
  'BufReadPre *.py,*.ipynb',
})
