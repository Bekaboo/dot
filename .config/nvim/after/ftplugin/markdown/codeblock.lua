-- Highlight code blocks and extend dashes in markdown files
-- Ported from https://github.com/lukas-reineke/headlines.nvim

local ft = vim.bo.ft
local loaded_flag = 'loaded_codeblock_' .. ft

-- Load plugin only once per filetype
if vim.g[loaded_flag] ~= nil then
  return
end
vim.g[loaded_flag] = true

local ns_name = string.format('my.ft.%s.codeblock', ft)
local ns = vim.api.nvim_create_namespace(ns_name)

local has_quantified_captures = vim.fn.has('nvim-0.11.0') == 1

local dash_string = '-'

---@class my.ft.markdown.codeblock.range
---@field start_row integer
---@field end_row integer

---Merge overlapping or adjacent buffer ranges.
---@param ranges my.ft.markdown.codeblock.range[]
---@return my.ft.markdown.codeblock.range[] merged
local function merge_ranges(ranges)
  table.sort(ranges, function(a, b)
    return a.start_row < b.start_row
  end)

  ---@type my.ft.markdown.codeblock.range[]
  local merged = {}
  for _, range in ipairs(ranges) do
    local previous = merged[#merged]
    if previous and range.start_row <= previous.end_row then
      previous.end_row = math.max(previous.end_row, range.end_row)
    else
      table.insert(merged, range)
    end
  end

  return merged
end

---Get the merged row ranges visible in normal windows for a buffer.
---@param buf integer
---@return my.ft.markdown.codeblock.range[] ranges visible, non-overlapping ranges.
---@return string range_id cache key containing the editor width and ranges.
local function get_visible_ranges(buf)
  ---@type my.ft.markdown.codeblock.range[]
  local ranges = {}

  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_is_valid(win) and vim.fn.win_gettype(win) == '' then
      local start_row, end_row = unpack(vim.api.nvim_win_call(win, function()
        return { vim.fn.line('w0') - 1, vim.fn.line('w$') }
      end))
      table.insert(ranges, { start_row = start_row, end_row = end_row })
    end
  end

  local merged = merge_ranges(ranges)

  local range_ids = vim.tbl_map(function(range)
    return string.format('%d:%d', range.start_row, range.end_row)
  end, merged)

  return merged,
    string.format('%d:%s', vim.go.columns, table.concat(range_ids, ','))
end

---@param buf? integer
local function refresh(buf)
  buf = vim._resolve_bufnr(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].ft ~= ft then
    return
  end

  if
    vim.b[buf].bigfile
    or vim.bo[buf].ft ~= ft
    or not vim.api.nvim_buf_is_loaded(buf)
    or vim.iter(vim.fn.win_findbuf(buf)):any(function(win)
      return vim.fn.win_gettype(win) ~= ''
    end)
  then
    return
  end

  local ranges, range_id = get_visible_ranges(buf)
  if vim.tbl_isempty(ranges) then
    return
  end

  if
    vim.b[buf].codeblock_refresh_changed_tick == vim.b[buf].changedtick
    and vim.b[buf].codeblock_refresh_range_id == range_id
  then
    return
  end

  local query = vim.npcall(
    vim.treesitter.query.parse,
    ft,
    [[
      (thematic_break) @dash
      (fenced_code_block) @codeblock
    ]]
  )
  if not query then
    return
  end

  local lang_tree = vim.treesitter.get_parser(buf, ft)
  if not lang_tree then
    return
  end

  local syntax_tree = lang_tree:parse()
  if not syntax_tree then
    return
  end

  vim.b[buf].codeblock_refresh_changed_tick = vim.b[buf].changedtick
  vim.b[buf].codeblock_refresh_range_id = range_id
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  vim.api.nvim_buf_call(buf, function()
    for _, range in ipairs(ranges) do
      for _, match, metadata in
        query:iter_matches(
          syntax_tree[1]:root(),
          buf,
          range.start_row,
          range.end_row
        )
      do
        for id, node in pairs(match) do
          if has_quantified_captures then
            node = node[#node]
          end

          local capture = query.captures[id]
          local start_row, _, end_row, _ = unpack(
            vim.tbl_extend(
              'force',
              { node:range() },
              (metadata[id] or {}).range or {}
            )
          )

          if capture == 'dash' and dash_string then
            pcall(vim.api.nvim_buf_set_extmark, buf, ns, start_row, 0, {
              virt_text = {
                { dash_string:rep(vim.go.columns), 'Dash' },
              },
              virt_text_pos = 'overlay',
              hl_mode = 'combine',
            })
          end

          if capture == 'codeblock' then
            local visible_start_row = math.max(start_row, range.start_row)
            local visible_end_row = math.min(end_row, range.end_row)
            pcall(
              vim.api.nvim_buf_set_extmark,
              buf,
              ns,
              visible_start_row,
              0,
              {
                end_col = 0,
                end_row = visible_end_row,
                hl_group = 'CodeBlock',
                hl_eol = true,
              }
            )

            local start_line = vim.api.nvim_buf_get_lines(
              buf,
              start_row,
              start_row + 1,
              false
            )[1]
            local _, padding = start_line:find('^ +')
            local codeblock_padding = math.max((padding or 0), 0)

            if codeblock_padding > 0 then
              for i = visible_start_row, visible_end_row - 1 do
                pcall(vim.api.nvim_buf_set_extmark, buf, ns, i, 0, {
                  virt_text = {
                    { string.rep(' ', codeblock_padding - 2), 'Normal' },
                  },
                  virt_text_win_col = 0,
                  priority = 1,
                })
              end
            end
          end
        end
      end
    end
  end)
end

local schedule_refresh = vim.schedule_wrap(refresh)
local buf = vim.api.nvim_get_current_buf()
if vim.v.vim_did_enter == 1 then
  schedule_refresh(buf)
else
  vim.api.nvim_create_autocmd('UIEnter', {
    once = true,
    callback = function()
      schedule_refresh(buf)
    end,
  })
end

local groupid = vim.api.nvim_create_augroup(ns_name, {})

vim.api.nvim_create_autocmd({
  'FileChangedShellPost',
  'InsertLeave',
  'TextChanged',
}, {
  group = groupid,
  desc = 'Refresh codeblocks and headlines.',
  callback = function(args)
    refresh(args.buf)
  end,
})

vim.api.nvim_create_autocmd('Syntax', {
  group = groupid,
  pattern = ft,
  desc = 'Refresh codeblocks and headlines.',
  callback = function(args)
    if vim.v.vim_did_enter == 0 then
      return
    end
    schedule_refresh(args.buf)
  end,
})

vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter' }, {
  group = groupid,
  desc = 'Refresh codeblocks and headlines.',
  callback = function(args)
    if vim.v.vim_did_enter == 0 or vim.bo[args.buf].ft ~= ft then
      return
    end
    schedule_refresh(args.buf)
  end,
})

vim.api.nvim_create_autocmd('WinScrolled', {
  group = groupid,
  desc = 'Refresh visible codeblocks and headlines.',
  callback = function(args)
    local win = tonumber(args.match)
    if not win or not vim.api.nvim_win_is_valid(win) then
      return
    end

    schedule_refresh(vim.api.nvim_win_get_buf(win))
  end,
})

vim.api.nvim_create_autocmd('WinResized', {
  group = groupid,
  desc = 'Refresh visible codeblocks and headlines.',
  callback = function()
    for _, win in ipairs(vim.v.event.windows or {}) do
      if vim.api.nvim_win_is_valid(win) then
        schedule_refresh(vim.api.nvim_win_get_buf(win))
      end
    end
  end,
})

local hl = require('my.utils.hl')

hl.persist(function()
  hl.set(0, 'CodeBlock', { link = 'CursorLine', default = true })
  hl.set(0, 'Dash', { link = 'LineNr', default = true })
  hl.set(0, 'markdownCode', { bg = 'CodeBlock' })
  hl.set(0, 'markdownCodeDelimiter', { bg = 'CodeBlock' })

  -- Treesitter hl
  hl.set(0, '@markup.raw.markdown_inline', {
    fg = 'String',
    bg = 'CodeBlock',
  })
end)
