-- Highlight code blocks and extend dashes in markdown files
-- Ported from https://github.com/lukas-reineke/headlines.nvim

local ft = vim.bo.ft
local loaded_flag = 'loaded_codeblocks' .. ft

if vim.g[loaded_flag] ~= nil then
  return
end
vim.g[loaded_flag] = true

local ns_name = ft .. 'CodeBlocks'
local ns = vim.api.nvim_create_namespace(ns_name)
local groupid = vim.api.nvim_create_augroup(ns_name, {})

local has_quantified_captures = vim.fn.has('nvim-0.11.0') == 1

---@param query string
---@return vim.treesitter.Query?
local function parse_query_save(query)
  local ok, parsed_query = pcall(vim.treesitter.query.parse, ft, query)
  if not ok then
    return nil
  end
  return parsed_query
end

local dash_string = '-'
local query = parse_query_save([[
  (thematic_break) @dash
  (fenced_code_block) @codeblock
]])

local function set_extmark(...)
  pcall(vim.api.nvim_buf_set_extmark, ...)
end

local function refresh()
  vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)

  if not query or vim.b.bigfile or vim.fn.win_gettype() ~= '' then
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local language_tree = vim.treesitter.get_parser(bufnr, ft)
  local syntax_tree = language_tree:parse()
  local root = syntax_tree[1]:root()
  local win_view = vim.fn.winsaveview()
  local left_offset = win_view.leftcol
  local width = vim.api.nvim_win_get_width(0)

  for _, match, metadata in query:iter_matches(root, bufnr) do
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
        set_extmark(bufnr, ns, start_row, 0, {
          virt_text = {
            { dash_string:rep(width), 'Dash' },
          },
          virt_text_pos = 'overlay',
          hl_mode = 'combine',
        })
      end

      if capture == 'codeblock' then
        set_extmark(bufnr, ns, start_row, 0, {
          end_col = 0,
          end_row = end_row,
          hl_group = 'CodeBlock',
          hl_eol = true,
        })

        local start_line =
          vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, false)[1]
        local _, padding = start_line:find('^ +')
        local codeblock_padding = math.max((padding or 0) - left_offset, 0)

        if codeblock_padding > 0 then
          for i = start_row, end_row - 1 do
            set_extmark(bufnr, ns, i, 0, {
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

local function set_default_hlgroups()
  vim.api.nvim_set_hl(0, 'CodeBlock', { link = 'CursorLine', default = true })
  vim.api.nvim_set_hl(0, 'Dash', { link = 'LineNr', default = true })
end

set_default_hlgroups()
vim.api.nvim_create_autocmd('ColorScheme', {
  group = groupid,
  desc = 'Set default highlight groups for headlines.nvim.',
  callback = set_default_hlgroups,
})

vim.api.nvim_create_autocmd({
  'FileChangedShellPost',
  'InsertLeave',
  'TextChanged',
}, {
  group = groupid,
  desc = 'Refresh headlines.',
  callback = refresh,
})

vim.api.nvim_create_autocmd('Syntax', {
  group = groupid,
  pattern = ft,
  desc = 'Refresh headlines.',
  callback = refresh,
})
