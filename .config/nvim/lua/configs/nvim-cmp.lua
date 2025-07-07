local cmp = require('cmp')
local icons = require('utils.static.icons')

-- Tabout structure, use plugin.tabout if available,
-- fallback to empty functions
local tabout = setmetatable({}, {
  __index = function(self, key)
    if rawget(self, '_init') then
      return
    end
    rawset(self, '_init', true)

    local has_tabout, tabout_plugin = pcall(require, 'plugin.tabout')
    if has_tabout then
      for k, v in pairs(tabout_plugin) do
        self[k] = v
      end
    else
      -- Fallback to empty functions
      self.setup = function() end
      self.jump = function() end
      self.get_jump_pos = function() end
    end
    return rawget(self, key)
  end,
})

-- Snippet engine structure, use LuaSnip if available,
-- fallback to `vim.snippet`
local snip = setmetatable({}, {
  __index = function(self, key)
    if rawget(self, '_init') then
      return
    end
    rawset(self, '_init', true)

    local has_luasnip, luasnip = pcall(require, 'luasnip')
    if has_luasnip then
      for k, v in pairs(luasnip) do
        self[k] = v
      end
    else
      -- Fallback to vim.snippet
      self.lsp_expand = vim.snippet.expand
      self.jumpable = function(direction)
        return vim.snippet.active({ direction = direction or 1 })
      end
      self.jump = vim.snippet.jump
      self.jump_destination = function() end
      self.expandable = function() end
      self.choice_active = function() end
      self.change_choice = function() end
    end
    return rawget(self, key)
  end,
})

---Choose the closer destination between two destinations
---@param dest1 number[]?
---@param dest2 number[]?
---@return number[]|nil
local function choose_closer(dest1, dest2)
  if not dest1 then
    return dest2
  end
  if not dest2 then
    return dest1
  end

  local current_pos = vim.api.nvim_win_get_cursor(0)
  local line_width = vim.api.nvim_win_get_width(0)
  local dist1 = math.abs(dest1[2] - current_pos[2])
    + math.abs(dest1[1] - current_pos[1]) * line_width
  local dist2 = math.abs(dest2[2] - current_pos[2])
    + math.abs(dest2[1] - current_pos[1]) * line_width
  if dist1 <= dist2 then
    return dest1
  else
    return dest2
  end
end

---Check if a node has length larger than 0
---@param node table
---@return boolean
local function snip_node_has_length(node)
  local start_pos, end_pos = node:get_buf_position()
  return start_pos[1] ~= end_pos[1] or start_pos[2] ~= end_pos[2]
end

---Convert a range into lsp format range
---@param range integer[][] 0-based range
---@return lsp_range_t
local function range_convert(range)
  local s = range[1]
  local e = range[2]
  return {
    start = { line = s[1], character = s[2] },
    ['end'] = { line = e[1], character = e[2] },
  }
end

---Check if range1 contains range2
---@param range1 integer[][] 0-based range
---@param range2 integer[][] 0-based range
---@return boolean
local function range_contains(range1, range2)
  return require('utils.lsp').range_contains(
    range_convert(range1),
    range_convert(range2)
  )
end

---Check if the cursor position is in the given range
---@param range integer[][] 0-based range
---@param cursor integer[]? 1,0-based cursor position
---@return boolean
local function in_range(range, cursor)
  return require('utils.lsp').range_contains_cursor(
    range_convert(range),
    cursor
  )
end

---Find the parent (a previous node that contains the current node) of the node
---@param node table current node
---@return table|nil
local function snip_node_find_parent(node)
  local range_start, range_end = node:get_buf_position()
  local prev = node.parent.snippet and node.parent.snippet.prev.prev
  while prev do
    local range_start_prev, range_end_prev = prev:get_buf_position()
    if
      range_contains(
        { range_start_prev, range_end_prev },
        { range_start, range_end }
      )
    then
      return prev
    end
    prev = prev.parent.snippet and prev.parent.snippet.prev.prev
  end
end

---Jump to the closer destination between a snippet and tabout
---@param snip_dest number[]?
---@param tabout_dest number[]?
---@param direction number 1 or -1
---@return boolean true if a jump is performed
local function jump_to_closer(snip_dest, tabout_dest, direction)
  direction = direction or 1
  local dest = choose_closer(snip_dest, tabout_dest)
  if not dest then
    return false
  end
  -- Prefer snippet jump to break ties
  if vim.deep_equal(dest, snip_dest) then
    snip.jump(direction)
  else
    tabout.jump(direction)
  end
  return true
end

local icon_cmd = icons.Cmd
local icon_calc = icons.Calculator
local icon_folder = icons.Folder
local icon_file = icons.File
local compltype_path = {
  dir = true,
  file = true,
  file_in_path = true,
  runtime = true,
}

---@return integer[] buffer numbers
local function get_bufnrs()
  return vim.b.bigfile and {} or { vim.api.nvim_get_current_buf() }
end

---Clamp the length of a field in a cmp item
---@param item table<string, any> cmp item
---@param field string which field in the cmp item to clamp
---@param min_width integer
---@param max_width integer
---@return nil
local function clamp(item, field, min_width, max_width)
  if not item[field] then
    return
  end
  -- In case that min_width > max_width
  if min_width > max_width then
    min_width, max_width = max_width, min_width
  end
  local field_str = item[field]
  local field_width = vim.fn.strdisplaywidth(field_str)
  if field_width > max_width then
    local former_width = math.floor(max_width * 0.6)
    local latter_width = math.max(0, max_width - former_width - 1)
    item[field] = field_str:sub(1, former_width)
      .. vim.trim(icons.Ellipsis)
      .. field_str:sub(-latter_width)
  elseif field_width < min_width then
    item[field] = string.format('%-' .. min_width .. 's', field_str)
  end
end

-- Wrap `vim.fn.getcompletion` to prevent errors when getting completions
-- from unmatched regex, see https://github.com/hrsh7th/cmp-cmdline/issues/101
vim.fn.getcompletion = (function(cb)
  return function(...)
    return vim.F.npcall(cb, ...) or {}
  end
end)(vim.fn.getcompletion)

---Wrapper of `cmp.select_next_item` and `cmp.select_prev_item` to use option
---`completeopt` as select behavior fallback
---@param cb function
---@return function
local function cmp_select_wrapper(cb)
  return function(option, ...)
    option = option or {}
    option.behavior = option.behavior
      or vim.tbl_contains(vim.opt.cot:get(), 'noinsert') and cmp.SelectBehavior.Select
      or cmp.SelectBehavior.Insert
    return cb(option, ...)
  end
end

cmp.select_prev_item = cmp_select_wrapper(cmp.select_prev_item)
cmp.select_next_item = cmp_select_wrapper(cmp.select_next_item)

---Check if currently in command line/window
---@return boolean
local function in_cmd()
  return vim.startswith(vim.fn.mode(), 'c')
    or vim.fn.win_gettype() == 'command'
end

cmp.setup({
  performance = {
    debounce = 0,
    throttle = 0,
    async_budget = 16,
    fetching_timeout = 64,
    max_view_entries = 64,
  },
  preselect = cmp.PreselectMode.None,
  matching = {
    disallow_partial_matching = false,
    disallow_partial_fuzzy_matching = false,
    disallow_prefix_unmatching = false,
    disallow_symbol_nonprefix_matching = false,
  },
  formatting = {
    fields = vim.g.has_nf and { 'kind', 'abbr', 'menu' } or nil,
    ---@param entry cmp.Entry
    ---@param item vim.CompletedItem
    ---@return vim.CompletedItem
    format = function(entry, item)
      local cmdcompltype = vim.fn.getcmdcompltype()
      local cmdcomplpath = compltype_path[cmdcompltype]
      -- Use special icons for file / directory completions
      if item.kind == 'File' or item.kind == 'Folder' or cmdcomplpath then
        -- Remove env vars and wildcards e.g.
        -- $VIMRUNTIME//usr/share/nvim -> /usr/share/nvim
        -- $VIMRUNTIME/**/usr/share/nvim -> /usr/share/nvim
        -- $VIMRUNTIME/**/ftplugin//usr/share/nvim/runtime/ftplugin/go.vim -> /usr/share/nvim/runtime/ftplugin/go.vim
        -- $PWD/./Users/user/.bashrc -> /Users/user/.bashrc
        -- **foo/bar -> foo/bar
        -- **/foo/bar -> foo/bar
        -- foo/**/foo/bar -> foo/bar
        -- ./**/./foo/bar -> ./foo/bar
        item.word = item.word
          :gsub('^%$[A-Za-z_]+.*//+', '/')
          :gsub('^%$[A-Za-z_]+.*%*+', '')
          :gsub('^%$[A-Za-z_]+/+%.?', '')
          :gsub('.*%*/*%.?/*', '')
          :gsub('/+', '/')
        item.abbr = item.word

        local stat = vim.uv.fs_stat(item.word)

        -- Escape special characters (e.g. '%', '$', '\') in file paths
        -- if in cmdline
        if cmdcomplpath and stat then
          item.word = vim.fn.fnameescape(item.word)
          item.abbr = item.word
        end

        -- Type of path, 'directory'/'file'/'symlink'/...
        if stat and stat.type == 'directory' then -- Directories
          item.kind = icon_folder
          item.kind_hl_group = 'CmpItemKindFolder'
        else -- Files
          local icon = icon_file
          local icon_hl = 'CmpItemKindFile'
          local devicons_ok, devicons = pcall(require, 'nvim-web-devicons')
          if devicons_ok then
            icon, icon_hl = devicons.get_icon(
              vim.fs.basename(item.word),
              vim.fn.fnamemodify(item.word, ':e'),
              { default = true }
            )
            icon = icon and icon .. ' '
          end
          item.kind = icon or icon_file
          item.kind_hl_group = icon_hl or 'CmpItemKindFile'
        end
      else -- Use special icons for some completions
        item.kind = entry.source.name == 'cmdline' and icon_cmd
          or entry.source.name == 'calc' and icon_calc
          or icons[item.kind]
          or ''
      end

      clamp(item, 'abbr', vim.o.pw, math.max(60, math.ceil(vim.o.co * 0.4)))
      clamp(item, 'menu', 0, math.max(16, math.ceil(vim.o.co * 0.2)))
      return item
    end,
  },
  snippet = {
    expand = function(args)
      snip.lsp_expand(args.body)
    end,
  },
  mapping = {
    ['<S-Tab>'] = cmp.mapping(function(fallback)
      -- In cmdline/cmdwin
      if in_cmd() then
        if cmp.visible() then
          cmp.select_prev_item()
          return
        end
        if tabout.get_jump_pos(-1) then
          tabout.jump(-1)
          return
        end
        cmp.complete()
        if not vim.tbl_contains(vim.opt.cot:get(), 'noselect') then
          cmp.select_prev_item()
        end
        return
      end

      -- In insert mode in normal buffers
      if not snip.jumpable(-1) then
        fallback()
        return
      end
      local tabout_dest = tabout.get_jump_pos(-1)
      local snip_dest = (function()
        local prev = snip.jump_destination(-1)
        if not prev then
          return
        end
        local _, dest = prev:get_buf_position()
        dest[1] = dest[1] + 1 -- (1, 0) indexed
        return dest
      end)()
      if not jump_to_closer(snip_dest, tabout_dest, -1) then
        fallback()
      end
    end, { 'i', 'c' }),
    ['<Tab>'] = cmp.mapping(function(fallback)
      -- In cmdline/cmdwin
      if in_cmd() then
        if cmp.visible() then
          cmp.select_next_item()
          return
        end
        if tabout.get_jump_pos(1) then
          tabout.jump(1)
          return
        end
        cmp.complete()
        if not vim.tbl_contains(vim.opt.cot:get(), 'noselect') then
          cmp.select_next_item()
        end
        return
      end

      -- In insert mode in normal buffers
      if snip.expandable() then
        snip.expand()
        return
      end
      if not snip.jumpable(1) then
        fallback()
        return
      end

      local tabout_dest = tabout.get_jump_pos(1)
      local snip_range = (function()
        local buf = vim.api.nvim_get_current_buf()
        local node = snip.session
          and snip.session.current_nodes
          and snip.session.current_nodes[buf]
        if not node then
          return
        end
        local parent = snip_node_find_parent(node)
        return snip_node_has_length(node) and { node:get_buf_position() }
          or parent and { parent:get_buf_position() }
      end)()

      -- Don't tabout if it jumps out current snippet range
      if
        not tabout_dest
        or not snip_range
        or not in_range(snip_range, tabout_dest)
      then
        snip.jump(1)
        return
      end

      -- If tabout destination is inside current snippet node, use `tabout.jump()`
      -- to jump inside current node without leaving it
      -- We can use `snip.jump()` once we reach the boundary of current
      -- snippet node
      -- |<------ current node range ----->|
      -- |.... ) .... ] ............ } ....|
      --        1      2              3      (tabout jump positions)
      local snip_dest = (function()
        local dest = snip.jump_destination(1):get_buf_position()
        return { dest[1] + 1, dest[2] } -- convert to (1,0) index
      end)()

      -- Jump to tabout or snippet destination depending on their distance
      -- from cursor, prefer snippet jump to break ties
      jump_to_closer(snip_dest, tabout_dest, 1)
    end, { 'i', 'c' }),
    ['<C-p>'] = {
      ['c'] = cmp.mapping.select_prev_item(),
      ['i'] = function()
        if cmp.visible() then
          cmp.select_prev_item()
          return
        end
        if snip.choice_active() then
          snip.change_choice(-1)
          return
        end
        cmp.complete()
        if not vim.tbl_contains(vim.opt.cot:get(), 'noselect') then
          cmp.select_prev_item()
        end
      end,
    },
    ['<C-n>'] = {
      ['c'] = cmp.mapping.select_next_item(),
      ['i'] = function()
        if cmp.visible() then
          cmp.select_next_item()
          return
        end
        if snip.choice_active() then
          snip.change_choice(1)
          return
        end
        cmp.complete()
        if not vim.tbl_contains(vim.opt.cot:get(), 'noselect') then
          cmp.select_next_item()
        end
      end,
    },
    ['<Up>'] = {
      ['c'] = cmp.mapping.select_prev_item(),
      ['i'] = function(fallback)
        if cmp.visible() then
          cmp.select_prev_item()
          return
        end
        if snip.choice_active() then
          snip.change_choice(-1)
          return
        end
        fallback()
      end,
    },
    ['<Down>'] = {
      ['c'] = cmp.mapping.select_next_item(),
      ['i'] = function(fallback)
        if cmp.visible() then
          cmp.select_next_item()
          return
        end
        if snip.choice_active() then
          snip.change_choice(1)
          return
        end
        fallback()
      end,
    },
    ['<PageDown>'] = cmp.mapping(
      cmp.mapping.select_next_item({
        count = vim.o.pumheight ~= 0 and math.ceil(vim.o.pumheight / 2) or 8,
      }),
      { 'i', 'c' }
    ),
    ['<PageUp>'] = cmp.mapping(
      cmp.mapping.select_prev_item({
        count = vim.o.pumheight ~= 0 and math.ceil(vim.o.pumheight / 2) or 8,
      }),
      { 'i', 'c' }
    ),
    ['<C-u>'] = cmp.mapping(cmp.mapping.scroll_docs(-4), { 'i', 'c' }),
    ['<C-d>'] = cmp.mapping(cmp.mapping.scroll_docs(4), { 'i', 'c' }),
    ['<C-e>'] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.abort()
        return
      end
      fallback()
    end, { 'i', 'c' }),
    ['<C-y>'] = cmp.mapping(cmp.mapping.confirm(), { 'i', 'c' }),
  },
  sources = {
    { name = 'luasnip', max_item_count = 3 },
    { name = 'nvim_lsp_signature_help' },
    { name = 'nvim_lsp' },
    { name = 'path' },
    {
      name = 'buffer',
      max_item_count = 8,
      option = {
        get_bufnrs = get_bufnrs,
      },
    },
    { name = 'calc' },
  },
  sorting = {
    ---@type table[]|function[]
    comparators = {
      cmp.config.compare.exact,
      cmp.config.compare.offset,
      cmp.config.compare.score,
      cmp.config.compare.locality,
      cmp.config.compare.recently_used,
      cmp.config.compare.length,
      cmp.config.compare.kind,
    },
  },
  -- cmp floating window config
  window = {
    documentation = {
      max_width = 80,
      max_height = 20,
      border = 'solid',
    },
  },
})

-- Use buffer source for `/`.
cmp.setup.cmdline('/', {
  enabled = true,
  sources = {
    {
      name = 'buffer',
      option = {
        get_bufnrs = get_bufnrs,
      },
    },
  },
})

cmp.setup.cmdline('?', {
  enabled = true,
  sources = {
    {
      name = 'buffer',
      option = {
        get_bufnrs = get_bufnrs,
      },
    },
  },
})

cmp.setup.cmdline(':', {
  enabled = function()
    -- Don't auto complete shell cmd which can be slow and block nvim
    -- on some systems, e.g. Windows, Android, etc.
    -- Commands that use shell cmd completion: `:!` and `:term`, etc.
    --
    -- cmp-cmdline provides an option `ignore_cmds` to disable auto
    -- completion for certain commands but that's insufficient because
    -- it only detect the start of cmd line instead of checking the
    -- actual completion type and will fail when the command is in the
    -- middle of the cmdline, e.g. (`:echo 'test' | !xxx` or `:hor term xxx`)
    if vim.fn.getcmdcompltype() ~= 'shellcmd' then
      return true
    end

    -- When `enabled()` returns false, nvim-cmp does not close previous
    -- completion menu, e.g. after typing 'term ' in cmdline the completion
    -- menu does not close, and nvim-cmp will keep auto-completing shellcmds,
    -- as a workaround we manually call `cmp.close()` if cmdline completion
    -- type is not 'shellcmd'
    --
    -- Also notice that we only close the completion menu when the character
    -- before the cursor is a space because we don't want the menu to close in
    -- the middle of a word, e.g. after pressing `<Tab>` in an empty cmdline
    -- and '!' is inserted as the first match and the completion type changes
    -- from 'command' to 'shellcmd'.
    --
    -- We can still manually trigger shell cmd completion so only close the
    -- completion window when the completion type has just changed to
    -- 'shellcmd' to avoid menu being closed when cycling through shell cmd
    -- completions
    if vim.fn.getcmdline():sub(vim.fn.getcmdpos() - 1) == ' ' then
      cmp.close()
    end

    -- HACK: nvim-cmp won't update the completion menu after manually
    -- triggering it if `enabled()` returns false
    if cmp.visible() then
      cmp.core:on_change('TextChanged')
    end

    return false
  end,
  sources = {
    {
      name = 'cmdline',
      option = { ignore_cmds = {} },
    },
  },
  sorting = {
    comparators = {
      ---@return boolean?
      function(...)
        -- For custom completions, keep original order
        local cmdcompltype = vim.fn.getcmdcompltype()
        if cmdcompltype == '' or vim.startswith(cmdcompltype, 'custom') then
          return cmp.config.compare.order(...)
        end
      end,
      cmp.config.compare.score,
      cmp.config.compare.exact,
      cmp.config.compare.recently_used,
    },
  },
})

-- cmp does not work with cmdline with type other than `:`, '/', and '?', e.g.
-- it does not respect the completion option of `input()`/`vim.ui.input()`, see
-- https://github.com/hrsh7th/nvim-cmp/issues/1690
-- https://github.com/hrsh7th/nvim-cmp/discussions/1073
cmp.setup.cmdline('@', { enabled = false })
cmp.setup.cmdline('>', { enabled = false })
cmp.setup.cmdline('-', { enabled = false })
cmp.setup.cmdline('=', { enabled = false })

-- Completion in DAP buffers
cmp.setup.filetype({ 'dap-repl', 'dapui_watches', 'dapui_hover' }, {
  enabled = true,
  sources = {
    { name = 'dap' },
  },
})

---Set telescope default hlgroups for a borderless view
---@return nil
local function set_default_hlgroups()
  vim.api.nvim_set_hl(0, 'CmpItemKindDefault', { link = 'Special' })
  vim.api.nvim_set_hl(0, 'CmpItemKindClass', { link = 'Type' })
  vim.api.nvim_set_hl(0, 'CmpItemKindConstant', { link = 'Constant' })
  vim.api.nvim_set_hl(0, 'CmpItemKindConstructor', { link = '@constructor' })
  vim.api.nvim_set_hl(0, 'CmpItemKindEnum', { link = 'Constant' })
  vim.api.nvim_set_hl(0, 'CmpItemKindEnumMember', { link = 'CmpItemKindEnum' })
  vim.api.nvim_set_hl(0, 'CmpItemKindFile', { link = 'Special' })
  vim.api.nvim_set_hl(0, 'CmpItemKindFolder', { link = 'Directory' })
  vim.api.nvim_set_hl(0, 'CmpItemKindFunction', { link = 'Function' })
  vim.api.nvim_set_hl(0, 'CmpItemKindInterface', { link = 'Type' })
  vim.api.nvim_set_hl(0, 'CmpItemKindKeyword', { link = 'Keyword' })
  vim.api.nvim_set_hl(0, 'CmpItemKindMethod', { link = 'Function' })
  vim.api.nvim_set_hl(0, 'CmpItemKindModule', { link = '@module' })
  vim.api.nvim_set_hl(0, 'CmpItemKindOperator', { link = 'Operator' })
  vim.api.nvim_set_hl(0, 'CmpItemKindString', { link = 'String' })
  vim.api.nvim_set_hl(0, 'CmpItemKindString', { link = 'String' })
  vim.api.nvim_set_hl(0, 'CmpItemKindStruct', { link = 'Type' })
  vim.api.nvim_set_hl(0, 'CmpItemKindText', { link = 'String' })
  vim.api.nvim_set_hl(0, 'CmpItemKindValue', { link = 'Number' })
end

set_default_hlgroups()

vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('CmpSetDefaultHlgroups', {}),
  desc = 'Set default hlgroups for nvim-cmp.',
  callback = set_default_hlgroups,
})
