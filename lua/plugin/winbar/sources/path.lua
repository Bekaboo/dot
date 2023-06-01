local configs = require('plugin.winbar.configs')
local bar = require('plugin.winbar.bar')

---Get icon and icon highlight group of a path
---@param path string
---@return string icon
---@return string? icon_hl
local function get_icon(path)
  local icon = configs.opts.icons.kinds.symbols.Folder
  local icon_hl = 'WinBarIconKindFolder'
  local stat = vim.loop.fs_stat(path)
  if configs.opts.icons.kinds.use_devicons then
    local devicons_ok, devicons = pcall(require, 'nvim-web-devicons')
    if devicons_ok and stat and stat.type ~= 'directory' then
      local devicon, devicon_hl = devicons.get_icon(
        vim.fs.basename(path),
        vim.fn.fnamemodify(path, ':e'),
        { default = true }
      )
      icon = devicon and devicon .. ' ' or icon
      icon_hl = devicon_hl
    end
  end
  return icon, icon_hl
end

---Convert a path to the winbar symbol structure
---@param path string full path
---@return winbar_symbol_t
local function convert(path)
  local icon, icon_hl = get_icon(path)
  return setmetatable({
    name = vim.fs.basename(path),
    icon = icon,
    icon_hl = icon_hl,
    actions = {
      ---@param symbol winbar_symbol_t
      jump = function(symbol)
        if symbol.entry then
          local current_menu = symbol.entry.menu
          while current_menu do
            current_menu:close()
            current_menu = current_menu.parent_menu
          end
          vim.cmd.edit(path)
        end
      end,
    },
  }, {
    ---@param self winbar_symbol_t
    __index = function(self, k)
      if k == 'children' then
        self.children = {}
        for name in vim.fs.dir(path) do
          if configs.opts.sources.path.filter(name) then
            table.insert(self.children, convert(path .. '/' .. name))
          end
        end
        return self.children
      end
      if k == 'siblings' or k == 'idx' then
        local parent_dir = vim.fs.dirname(path)
        self.siblings = {}
        self.idx = 1
        for idx, name in vim.iter(vim.fs.dir(parent_dir)):enumerate() do
          if configs.opts.sources.path.filter(name) then
            table.insert(self.siblings, convert(parent_dir .. '/' .. name))
            if name == self.name then
              self.idx = idx
            end
          end
        end
        return self[k]
      end
    end,
  })
end

---Get list of winbar symbols of the parent directories of given buffer
---@param buf integer buffer handler
---@param _ integer[] cursor position, ignored
---@return winbar_symbol_t[] winbar symbols
local function get_symbols(buf, _)
  local symbols = {} ---@type winbar_symbol_t[]
  local current_path = vim.fs.normalize(
    vim.fn.fnamemodify((vim.api.nvim_buf_get_name(buf)), ':p')
  )
  while
    current_path ~= '.'
    and current_path ~= '/'
    and current_path
      ~= vim.fs.normalize(
        configs.eval(configs.opts.sources.path.relative_to, buf)
      )
  do
    table.insert(symbols, 1, bar.winbar_symbol_t:new(convert(current_path)))
    current_path = vim.fs.dirname(current_path)
  end
  return symbols
end

return {
  get_symbols = get_symbols,
}
