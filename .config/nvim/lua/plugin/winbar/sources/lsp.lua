local utils = require('plugin.winbar.utils')
local configs = require('plugin.winbar.configs')
local bar = require('plugin.winbar.bar')
local groupid = vim.api.nvim_create_augroup('WinBarLsp', {})
local initialized = false

---@type table<integer, lsp_document_symbol_t[]>
local lsp_buf_symbols = {}
setmetatable(lsp_buf_symbols, {
  __index = function(_, k)
    lsp_buf_symbols[k] = {}
    return lsp_buf_symbols[k]
  end,
})

---@alias lsp_client_t table

---@class lsp_range_t
---@field start {line: integer, character: integer}
---@field end {line: integer, character: integer}

---@class lsp_location_t
---@field uri string
---@field range lsp_range_t

---@class lsp_document_symbol_t
---@field name string
---@field kind integer
---@field tags? table
---@field deprecated? boolean
---@field detail? string
---@field range? lsp_range_t
---@field selectionRange? lsp_range_t
---@field children? lsp_document_symbol_t[]

---@class lsp_symbol_information_t
---@field name string
---@field kind integer
---@field tags? table
---@field deprecated? boolean
---@field location? lsp_location_t
---@field containerName? string

---@class lsp_symbol_information_tree_t: lsp_symbol_information_t
---@field parent? lsp_symbol_information_tree_t
---@field children? lsp_symbol_information_tree_t[]
---@field siblings? lsp_symbol_information_tree_t[]

---@alias lsp_symbol_t lsp_document_symbol_t|lsp_symbol_information_t

-- Map symbol number to symbol kind
-- stylua: ignore start
local symbol_kind_names = setmetatable({
  [1]  = 'File',
  [2]  = 'Module',
  [3]  = 'Namespace',
  [4]  = 'Package',
  [5]  = 'Class',
  [6]  = 'Method',
  [7]  = 'Property',
  [8]  = 'Field',
  [9]  = 'Constructor',
  [10] = 'Enum',
  [11] = 'Interface',
  [12] = 'Function',
  [13] = 'Variable',
  [14] = 'Constant',
  [15] = 'String',
  [16] = 'Number',
  [17] = 'Boolean',
  [18] = 'Array',
  [19] = 'Object',
  [20] = 'Keyword',
  [21] = 'Null',
  [22] = 'EnumMember',
  [23] = 'Struct',
  [24] = 'Event',
  [25] = 'Operator',
  [26] = 'TypeParameter',
}, {
  __index = function()
    return ''
  end,
})
-- stylua: ignore end

---Return type of the symbol table
---@param symbols lsp_symbol_t[] symbol table
---@return string? symbol type
local function symbol_type(symbols)
  if symbols[1] and symbols[1].location then
    return 'SymbolInformation'
  elseif symbols[1] and symbols[1].range then
    return 'DocumentSymbol'
  end
end

---Convert LSP DocumentSymbol into winbar symbol
---@param document_symbol lsp_document_symbol_t LSP DocumentSymbol
---@param buf integer buffer number
---@param win integer window number
---@param siblings lsp_document_symbol_t[]? siblings of the symbol
---@param idx integer? index of the symbol in siblings
---@return winbar_symbol_t
local function convert_document_symbol(
  document_symbol,
  buf,
  win,
  siblings,
  idx
)
  local kind = symbol_kind_names[document_symbol.kind]
  return bar.winbar_symbol_t:new(setmetatable({
    buf = buf,
    win = win,
    name = document_symbol.name,
    icon = configs.opts.icons.kinds.symbols[kind],
    icon_hl = 'WinBarIconKind' .. kind,
    range = document_symbol.range,
    sibling_idx = idx,
  }, {
    __index = function(self, k)
      if k == 'children' then
        if not document_symbol.children then
          return nil
        end
        self.children = vim.tbl_map(function(child)
          return convert_document_symbol(child, buf, win)
        end, document_symbol.children)
        return self.children
      elseif k == 'siblings' then
        if not siblings then
          return nil
        end
        self.siblings = vim.tbl_map(function(sibling)
          return convert_document_symbol(sibling, buf, win, siblings)
        end, siblings)
        return self.siblings
      end
    end,
  }))
end

---Convert LSP DocumentSymbol[] into a list of winbar symbols
---Side effect: change winbar_symbols
---LSP Specification document: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/
---@param lsp_symbols lsp_document_symbol_t[]
---@param winbar_symbols winbar_symbol_t[] (reference to) winbar symbols
---@param buf integer buffer number
---@param win integer window number
---@param cursor integer[] cursor position
local function convert_document_symbol_list(
  lsp_symbols,
  winbar_symbols,
  buf,
  win,
  cursor
)
  if #winbar_symbols >= configs.opts.sources.lsp.max_depth then
    return
  end

  -- Parse in reverse order so that the symbol with the largest start position
  -- is preferred
  for idx, symbol in vim.iter(lsp_symbols):enumerate():rev() do
    if utils.lsp.range_contains_cursor(symbol.range, cursor) then
      if
        vim.tbl_contains(
          configs.opts.sources.lsp.valid_symbols,
          symbol_kind_names[symbol.kind]
        )
      then
        table.insert(
          winbar_symbols,
          convert_document_symbol(symbol, buf, win, lsp_symbols, idx)
        )
      end
      if symbol.children then
        convert_document_symbol_list(
          symbol.children,
          winbar_symbols,
          buf,
          win,
          cursor
        )
      end
      return
    end
  end
end

---Convert LSP SymbolInformation[] into DocumentSymbol[]
---@param symbols lsp_symbol_t LSP symbols
---@return lsp_document_symbol_t[]
local function unify(symbols)
  if symbol_type(symbols) == 'DocumentSymbol' or vim.tbl_isempty(symbols) then
    return symbols
  end
  -- Convert SymbolInformation[] to DocumentSymbol[]
  for _, sym in ipairs(symbols) do
    sym.range = sym.location.range
  end
  local document_symbols = { symbols[1] }
  -- According to the result get from pylsp, the SymbolInformation list is
  -- ordered in increasing order by the start position of the range, so a
  -- symbol can only be a child or a sibling of the previous symbol in the
  -- same list
  for list_idx, sym in vim.iter(symbols):enumerate():skip(1) do
    local prev = symbols[list_idx - 1] --[[@as lsp_symbol_information_tree_t]]
    -- If the symbol is a child of the previous symbol
    if utils.lsp.range_contains(prev.location.range, sym.location.range) then
      sym.parent = prev
    else -- Else the symbol is a sibling of the previous symbol
      sym.parent = prev.parent
    end
    if sym.parent then
      sym.parent.children = sym.parent.children or {}
      table.insert(sym.parent.children, sym)
    else
      table.insert(document_symbols, sym)
    end
  end
  return document_symbols
end

---Update LSP symbols for given buffer
---Side effect: update symbol_list
---@param buf integer buffer handler
---@param ttl integer? limit the number of recursive requests, default 60
local function update_symbols(buf, ttl)
  ttl = ttl or configs.opts.sources.lsp.request.ttl_init
  if ttl <= 0 or not vim.api.nvim_buf_is_valid(buf) then
    lsp_buf_symbols[buf] = nil
    return
  end

  local function _defer_update()
    vim.defer_fn(function()
      update_symbols(buf, ttl - 1)
    end, configs.opts.sources.lsp.request.interval)
  end

  local client = vim.tbl_filter(
    function(client)
      return client:supports_method('textDocument/documentSymbol')
    end,
    vim.lsp.get_clients({
      bufnr = buf,
    })
  )[1]
  if not client then
    _defer_update()
    return
  end

  client:request(
    'textDocument/documentSymbol',
    { textDocument = vim.lsp.util.make_text_document_params(buf) },
    function(err, symbols, _)
      if err or not symbols or vim.tbl_isempty(symbols) then
        _defer_update()
        return
      end
      lsp_buf_symbols[buf] = unify(symbols)
    end,
    buf
  )
end

---Attach LSP symbol getter to buffer
---@param buf integer buffer handler
local function attach(buf)
  if vim.b[buf].winbar_lsp_attached then
    return
  end

  update_symbols(buf)
  vim.b[buf].winbar_lsp_attached =
    vim.api.nvim_create_autocmd(configs.opts.bar.update_events.buf, {
      group = groupid,
      buffer = buf,
      callback = function(args)
        update_symbols(args.buf)
      end,
    })
end

---Detach LSP symbol getter from buffer
---@param buf integer buffer handler
local function detach(buf)
  if vim.b[buf].winbar_lsp_attached then
    vim.api.nvim_del_autocmd(vim.b[buf].winbar_lsp_attached)
    vim.b[buf].winbar_lsp_attached = nil
    lsp_buf_symbols[buf] = nil
    for _, winbar in pairs(_G._winbar.bars[buf]) do
      winbar:update()
    end
  end
end

---Initialize lsp source
---@return nil
local function init()
  if initialized then
    return
  end
  initialized = true
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local clients = vim.tbl_filter(function(client)
      return client:supports_method('textDocument/documentSymbol')
    end, vim.lsp.get_clients({ bufnr = buf }))
    if not vim.tbl_isempty(clients) then
      attach(buf)
    end
  end
  vim.api.nvim_create_autocmd({ 'LspAttach' }, {
    desc = 'Attach LSP symbol getter to buffer when an LS that supports documentSymbol attaches.',
    group = groupid,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and client:supports_method('textDocument/documentSymbol') then
        attach(args.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ 'LspDetach' }, {
    desc = 'Detach LSP symbol getter from buffer when no LS supporting documentSymbol is attached.',
    group = groupid,
    callback = function(args)
      if
        vim.tbl_isempty(vim.tbl_filter(function(client)
          return client:supports_method('textDocument/documentSymbol')
            and client.id ~= args.data.client_id
        end, vim.lsp.get_clients({ bufnr = args.buf })))
      then
        detach(args.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufUnload', 'BufWipeOut' }, {
    desc = 'Detach LSP symbol getter from buffer on buffer delete/unload/wipeout.',
    group = groupid,
    callback = function(args)
      detach(args.buf)
    end,
  })
end

---Get winbar symbols from buffer according to cursor position
---@param buf integer buffer handler
---@param win integer window handler
---@param cursor integer[] cursor position
---@return winbar_symbol_t[] symbols winbar symbols
local function get_symbols(buf, win, cursor)
  if not initialized then
    init()
  end
  local result = {}
  convert_document_symbol_list(lsp_buf_symbols[buf], result, buf, win, cursor)
  utils.bar.set_min_widths(result, configs.opts.sources.lsp.min_widths)
  return result
end

return {
  get_symbols = get_symbols,
}
