local cmp = require('cmp')
local cmp_core = require('cmp.core')
local luasnip = require('luasnip')
local tabout = require('plugin.tabout')
local icons = require('utils.static.icons')

---Hack: `nvim_lsp` and `nvim_lsp_signature_help` source still use
---deprecated `vim.lsp.buf_get_clients()`, which is slower due to
---the deprecation and version check in that function. Overwrite
---it using `vim.lsp.get_clients()` to improve performance.
---@diagnostic disable-next-line: duplicate-set-field
function vim.lsp.buf_get_clients(bufnr)
  return vim.lsp.get_clients({ buffer = bufnr })
end

---@type string?
local last_key

vim.on_key(function(k)
  last_key = k
end)

---@type integer
local last_changed = 0
local _cmp_on_change = cmp_core.on_change

---Improves performance when inserting in large files
---@diagnostic disable-next-line: duplicate-set-field
function cmp_core.on_change(self, trigger_event)
  -- Don't know why but inserting spaces/tabs causes higher latency than other
  -- keys, e.g. when holding down 's' the interval between keystrokes is less
  -- than 32ms (80 repeats/s keyboard), but when holding spaces/tabs the
  -- interval increases to 100ms, guess is is due to some other plugins that
  -- triggers on spaces/tabs
  -- Spaces/tabs are not useful in triggering completions in insert mode but can
  -- be useful in command-line autocompletion, so ignore them only when not in
  -- command-line mode
  if
    not vim.startswith(vim.fn.mode(), 'c')
    and (last_key == ' ' or last_key == '\t')
  then
    return
  end

  local now = vim.uv.now()
  local fast_typing = now - last_changed < 32
  last_changed = now

  if not fast_typing or trigger_event ~= 'TextChanged' or cmp.visible() then
    _cmp_on_change(self, trigger_event)
    return
  end

  vim.defer_fn(function()
    if last_changed == now then
      _cmp_on_change(self, trigger_event)
    end
  end, 200)
end

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
local function node_has_length(node)
  local start_pos, end_pos = node:get_buf_position()
  return start_pos[1] ~= end_pos[1] or start_pos[2] ~= end_pos[2]
end

---Check if range1 contains range2
---If range1 == range2, return true
---@param range1 integer[][] 0-based range
---@param range2 integer[][] 0-based range
---@return boolean
local function range_contains(range1, range2)
  -- stylua: ignore start
  return (
    range2[1][1] > range1[1][1]
    or (range2[1][1] == range1[1][1]
        and range2[1][2] >= range1[1][2])
    )
    and (
      range2[1][1] < range1[2][1]
      or (range2[1][1] == range1[2][1]
          and range2[1][2] <= range1[2][2])
    )
    and (
      range2[2][1] > range1[1][1]
      or (range2[2][1] == range1[1][1]
          and range2[2][2] >= range1[1][2])
    )
    and (
      range2[2][1] < range1[2][1]
      or (range2[2][1] == range1[2][1]
          and range2[2][2] <= range1[2][2])
    )
  -- stylua: ignore end
end

---Check if the cursor position is in the given range
---@param range integer[][] 0-based range
---@param cursor integer[] 1,0-based cursor position
---@return boolean
local function in_range(range, cursor)
  local cursor0 = { cursor[1] - 1, cursor[2] }
  -- stylua: ignore start
  return (
    cursor0[1] > range[1][1]
    or (cursor0[1] == range[1][1]
        and cursor0[2] >= range[1][2])
    )
    and (
      cursor0[1] < range[2][1]
      or (cursor0[1] == range[2][1]
          and cursor0[2] <= range[2][2])
    )
  -- stylua: ignore end
end

---Find the parent (a previous node that contains the current node) of the node
---@param node table current node
---@return table|nil
local function node_find_parent(node)
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
---@param snip_dest number[]
---@param tabout_dest number[]?
---@param direction number 1 or -1
---@return boolean true if a jump is performed
local function jump_to_closer(snip_dest, tabout_dest, direction)
  direction = direction or 1
  local dest = choose_closer(snip_dest, tabout_dest)
  if not dest then
    return false
  end
  if vim.deep_equal(dest, tabout_dest) then
    tabout.jump(direction)
  else
    luasnip.jump(direction)
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
    item[field] = string.format(
      '%s…%s',
      field_str:sub(1, former_width),
      field_str:sub(-latter_width)
    )
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

cmp.setup({
  enabled = function()
    return not vim.b.bigfile
  end,
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
  confirmation = {
    default_behavior = cmp.ConfirmBehavior.Replace,
    get_commit_characters = function(commit_characters)
      vim.list_extend(commit_characters, { '.', ':', '(', '{' })
      return commit_characters
    end,
  },
  formatting = {
    fields = vim.g.has_nf and { 'kind', 'abbr', 'menu' } or nil,
    format = function(entry, item)
      local cmdcompltype = vim.fn.getcmdcompltype()
      local cmdcomplpath = compltype_path[cmdcompltype]
      -- Use special icons for file / directory completions
      if item.kind == 'File' or item.kind == 'Folder' or cmdcomplpath then
        local stat = vim.uv.fs_stat(vim.fs.normalize(item.word))

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
      require('luasnip').lsp_expand(args.body)
    end,
  },
  mapping = {
    ['<S-Tab>'] = {
      ['c'] = function()
        if cmp.visible() then
          cmp.select_prev_item()
        elseif tabout.get_jump_pos(-1) then
          tabout.jump(-1)
        else
          cmp.complete()
        end
      end,
      ['i'] = function(fallback)
        if luasnip.locally_jumpable(-1) then
          local prev = luasnip.jump_destination(-1)
          local _, snip_dest_end = prev:get_buf_position()
          snip_dest_end[1] = snip_dest_end[1] + 1 -- (1, 0) indexed
          local tabout_dest = tabout.get_jump_pos(-1)
          if not jump_to_closer(snip_dest_end, tabout_dest, -1) then
            fallback()
          end
        else
          fallback()
        end
      end,
    },
    ['<Tab>'] = {
      ['c'] = function()
        if cmp.visible() then
          cmp.select_next_item()
        elseif tabout.get_jump_pos(1) then
          tabout.jump(1)
        else
          cmp.complete()
        end
      end,
      ['i'] = function(fallback)
        if luasnip.expandable() then
          luasnip.expand()
        elseif luasnip.locally_jumpable(1) then
          local buf = vim.api.nvim_get_current_buf()
          local current = luasnip.session.current_nodes[buf]
          local parent = node_find_parent(current)
          local range = node_has_length(current)
              and { current:get_buf_position() }
            or parent and { parent:get_buf_position() }
          local tabout_dest = tabout.get_jump_pos(1)
          if range and tabout_dest and in_range(range, tabout_dest) then
            tabout.jump(1)
          else
            luasnip.jump(1)
          end
        else
          fallback()
        end
      end,
    },
    ['<C-p>'] = {
      ['c'] = cmp.mapping.select_prev_item(),
      ['i'] = function()
        if cmp.visible() then
          cmp.select_prev_item()
        elseif luasnip.choice_active() then
          luasnip.change_choice(-1)
        else
          cmp.complete()
        end
      end,
    },
    ['<C-n>'] = {
      ['c'] = cmp.mapping.select_next_item(),
      ['i'] = function()
        if cmp.visible() then
          cmp.select_next_item()
        elseif luasnip.choice_active() then
          luasnip.change_choice(1)
        else
          cmp.complete()
        end
      end,
    },
    ['<Down>'] = cmp.mapping(cmp.mapping.select_next_item(), { 'i', 'c' }),
    ['<Up>'] = cmp.mapping(cmp.mapping.select_prev_item(), { 'i', 'c' }),
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
      else
        fallback()
      end
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
      ---Prioritize snippet over other completions
      ---@param e1 cmp.Entry
      ---@param e2 cmp.Entry
      ---@return boolean?
      function(e1, e2)
        local kind1 = e1:get_kind() --- @type lsp.CompletionItemKind|number
        local kind2 = e2:get_kind() --- @type lsp.CompletionItemKind|number

        local types = require('cmp.types')
        kind1 = kind1 == types.lsp.CompletionItemKind.Text and 100 or kind1
        kind2 = kind2 == types.lsp.CompletionItemKind.Text and 100 or kind2
        if kind1 == kind2 then
          return
        end

        if kind1 == types.lsp.CompletionItemKind.Snippet then
          return true
        end

        if kind2 == types.lsp.CompletionItemKind.Snippet then
          return false
        end
      end,
      cmp.config.compare.score,
      cmp.config.compare.exact,
      cmp.config.compare.locality,
      cmp.config.compare.kind,
      cmp.config.compare.recently_used,
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
-- Use cmdline & path source for ':'.
cmp.setup.cmdline(':', {
  enabled = true,
  sources = {
    {
      name = 'cmdline',
      option = {
        ignore_cmds = {},
      },
      group_index = 2,
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
  local hl = require('utils.hl')
  hl.set_default(0, 'CmpItemKindDefault', { link = 'Special' })
  hl.set_default(0, 'CmpItemKindClass', { link = 'Type' })
  hl.set_default(0, 'CmpItemKindConstant', { link = 'Constant' })
  hl.set_default(0, 'CmpItemKindConstructor', { link = '@constructor' })
  hl.set_default(0, 'CmpItemKindEnum', { link = 'Constant' })
  hl.set_default(0, 'CmpItemKindEnumMember', { link = 'CmpItemKindEnum' })
  hl.set_default(0, 'CmpItemKindFile', { link = 'Special' })
  hl.set_default(0, 'CmpItemKindFolder', { link = 'Directory' })
  hl.set_default(0, 'CmpItemKindFunction', { link = 'Function' })
  hl.set_default(0, 'CmpItemKindInterface', { link = 'Type' })
  hl.set_default(0, 'CmpItemKindKeyword', { link = 'Keyword' })
  hl.set_default(0, 'CmpItemKindMethod', { link = 'Function' })
  hl.set_default(0, 'CmpItemKindModule', { link = '@module' })
  hl.set_default(0, 'CmpItemKindOperator', { link = 'Operator' })
  hl.set_default(0, 'CmpItemKindString', { link = 'String' })
  hl.set_default(0, 'CmpItemKindString', { link = 'String' })
  hl.set_default(0, 'CmpItemKindStruct', { link = 'Type' })
  hl.set_default(0, 'CmpItemKindText', { link = 'String' })
  hl.set_default(0, 'CmpItemKindValue', { link = 'Number' })
end

set_default_hlgroups()

vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('CmpSetDefaultHlgroups', {}),
  desc = 'Set default hlgroups for nvim-cmp.',
  callback = set_default_hlgroups,
})
