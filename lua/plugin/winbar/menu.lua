local bar = require('plugin.winbar.bar')
local groupid = vim.api.nvim_create_augroup('WinBarMenu', {})

---Lookup table for winbar menus
---@type table<integer, winbar_menu_t>
_G.winbar.menus = {}

---@param value number
---@param min number
---@param max number
local function bound(value, min, max)
  -- In case min > max
  local lower_bound = math.min(min, max)
  local upper_bound = math.max(min, max)
  return math.min(math.max(value, lower_bound), upper_bound)
end

---@class winbar_menu_hl_info_t
---@field start integer
---@field end integer
---@field hlgroup string
---@field ns integer? namespace id, nil if using default namespace

---@class winbar_menu_entry_t
---@field separator winbar_symbol_t
---@field padding {left: integer, right: integer}
---@field components winbar_symbol_t[]
---@field menu winbar_menu_t? the menu the entry belongs to
---@field idx integer? the index of the entry in the menu
local winbar_menu_entry_t = {}
winbar_menu_entry_t.__index = winbar_menu_entry_t

---Create a winbar menu entry instance
---@param opts winbar_menu_entry_t?
---@return winbar_menu_entry_t
function winbar_menu_entry_t:new(opts)
  local entry = setmetatable(
    vim.tbl_deep_extend('force', {
      separator = bar.winbar_symbol_t:new({
        icon = ' ',
        icon_hl = 'WinBarIconUISeparator',
      }),
      padding = {
        left = 1,
        right = 1,
      },
      components = {},
    }, opts),
    self
  )
  for idx, component in ipairs(entry.components) do
    component.entry = entry
    component.entry_idx = idx
  end
  return entry
end

---Concatenate inside a winbar menu entry to get the final string
---and highlight information of the entry
---@return string str
---@return winbar_menu_hl_info_t[] hl_info
function winbar_menu_entry_t:cat()
  local components_with_sep = {} ---@type winbar_symbol_t[]
  for component_idx, component in ipairs(self.components) do
    if component_idx > 1 then
      table.insert(components_with_sep, self.separator)
    end
    table.insert(components_with_sep, component)
  end
  local str = ''
  local hl_info = {}
  for _, component in ipairs(components_with_sep) do
    if component.icon_hl then
      table.insert(hl_info, {
        start = #str,
        ['end'] = #str + #component.icon,
        hlgroup = component.icon_hl,
      })
    end
    if component.name_hl then
      table.insert(hl_info, {
        start = #str + #component.icon + 1,
        ['end'] = #str + #component.icon + #component.name + 1,
        hlgroup = component.name_hl,
      })
    end
    str = str .. component:cat(true)
  end
  return string.rep(' ', self.padding.left) .. str .. string.rep(
    ' ',
    self.padding.right
  ),
    hl_info
end

---Get the display length of the winbar menu entry
---@return number
function winbar_menu_entry_t:displaywidth()
  return vim.fn.strdisplaywidth((self:cat()))
end

---Get the byte length of the winbar menu entry
---@return number
function winbar_menu_entry_t:bytewidth()
  return #(self:cat())
end

---Get the first clickable component in the winbar menu entry
---@param offset integer? offset from the beginning of the entry, default 0
---@return winbar_symbol_t?
function winbar_menu_entry_t:first_clickable(offset)
  offset = offset or 0
  for _, component in ipairs(self.components) do
    offset = offset - component:bytewidth()
    if offset <= 0 and component.on_click then
      return component
    end
  end
end

---@class winbar_menu_opts_t
---@field is_open boolean?
---@field entries winbar_menu_entry_t[]?
---@field win_configs table? window configuration
---@field cursor integer[]? initial cursor position
---@field prev_win integer? previous window

---@class winbar_menu_t
---@field is_open boolean?
---@field entries winbar_menu_entry_t[]
---@field win_configs table window configuration, value can be a function
---@field _win_configs table evaluated window configuration
---@field cursor integer[]? initial cursor position
---@field prev_win integer? previous window, assigned when calling new() or automatically determined in open()
---@field sub_menu winbar_menu_t? submenu, assigned when calling new() or automatically determined when a new menu opens
---@field parent_menu winbar_menu_t? parent menu, assigned when calling new() or automatically determined in open()
---@field clicked_at integer[]? last position where the menu was clicked
local winbar_menu_t = {}
winbar_menu_t.__index = winbar_menu_t

---Create a winbar menu instance
---@param opts winbar_menu_opts_t?
---@return winbar_menu_t
function winbar_menu_t:new(opts)
  local winbar_menu = setmetatable(
    vim.tbl_deep_extend('force', {
      entries = {},
      win_configs = {
        ---@param this winbar_menu_t
        row = function(this)
          return this.parent_menu
              and this.parent_menu.clicked_at
              and this.parent_menu.clicked_at[1] - vim.fn.line('w0')
            or 1
        end,
        ---@param this winbar_menu_t
        col = function(this)
          return this.parent_menu and this.parent_menu._win_configs.width or 0
        end,
        ---@param this winbar_menu_t
        relative = function(this)
          return this.parent_menu and 'win' or 'mouse'
        end,
        ---@param this winbar_menu_t
        win = function(this)
          return this.parent_menu and this.parent_menu.win
        end,
        border = 'none',
        style = 'minimal',
        ---@param this winbar_menu_t
        height = function(this)
          return bound(
            #this.entries,
            1,
            vim.go.pumheight ~= 0 and vim.go.pumheight
              or math.floor(vim.go.lines / 4)
          )
        end,
        ---@param this winbar_menu_t
        width = function(this)
          local entry_lengths = vim.tbl_map(function(entry)
            return entry:displaywidth()
          end, this.entries)
          if vim.tbl_isempty(entry_lengths) then
            return vim.go.pumwidth
          end
          return bound(
            math.max(unpack(entry_lengths)),
            vim.go.pumwidth,
            math.floor(vim.go.columns / 2)
          )
        end,
      },
    }, opts or {}),
    winbar_menu_t
  )
  for idx, entry in ipairs(winbar_menu.entries) do
    entry.menu = winbar_menu
    entry.idx = idx
  end
  return winbar_menu
end

---Delete a winbar menu
---@return nil
function winbar_menu_t:del()
  if self.sub_menu then
    self.sub_menu:del()
    self.sub_menu = nil
  end
  self:close()
  if self.buf then
    vim.api.nvim_buf_delete(self.buf, {})
    self.buf = nil
  end
end

---Evaluate window configurations
---Side effects: update self._win_configs
---@return nil
---@see vim.api.nvim_open_win
function winbar_menu_t:eval_win_config()
  -- Evaluate function-valued window configurations
  self._win_configs = {}
  for k, config in pairs(self.win_configs) do
    if type(config) == 'function' then
      self._win_configs[k] = config(self)
    else
      self._win_configs[k] = config
    end
  end
end

---Get the component at the given position in the winbar menu
---@param pos integer[] {row: integer, col: integer}, 1-indexed, byte-indexed
---@return winbar_symbol_t?
function winbar_menu_t:get_component_at(pos)
  if not self.entries or vim.tbl_isempty(self.entries) then
    return nil
  end
  local row = pos[1]
  local col = pos[2]
  local entry = self.entries[row]
  if not entry or not entry.components then
    return nil
  end
  local col_offset = entry.padding.left
  for _, component in ipairs(entry.components) do
    local component_len = component:bytewidth()
    if col <= col_offset + component_len then -- Look-ahead
      return component
    end
    col_offset = col_offset + component_len
  end
  return nil
end

---"Click" the component at the given position in the winbar menu
---Side effects: update self.clicked_at
---@param pos integer[] {row: integer, col: integer}, 1-indexed
---@param min_width integer?
---@param n_clicks integer?
---@param button string?
---@param modifiers string?
function winbar_menu_t:click_at(pos, min_width, n_clicks, button, modifiers)
  self.clicked_at = pos
  vim.api.nvim_win_set_cursor(self.win, pos)
  local component = self:get_component_at(pos)
  if component then
    if component.on_click then
      component:on_click(min_width, n_clicks, button, modifiers)
    end
  end
end

---"Click" the component in the winbar menu
---Side effects: update self.clicked_at
---@param symbol winbar_symbol_t
---@param min_width integer?
---@param n_clicks integer?
---@param button string?
---@param modifiers string?
function winbar_menu_t:click_on(symbol, min_width, n_clicks, button, modifiers)
  local row = symbol.entry.idx
  local col = 0
  for idx, component in ipairs(symbol.entry.components) do
    if idx == symbol.entry_idx then
      break
    end
    col = col + component:bytewidth()
  end
  self.clicked_at = { row, col }
  if symbol then
    if symbol.on_click then
      symbol:on_click(min_width, n_clicks, button, modifiers)
    end
  end
end

---Add highlight to a range in the menu buffer
---@param line integer 1-indexed
---@param hl_info winbar_menu_hl_info_t
---@return nil
function winbar_menu_t:hl_line_range(line, hl_info)
  if not self.buf then
    return
  end
  vim.api.nvim_buf_add_highlight(
    self.buf,
    hl_info.ns or -1,
    hl_info.hlgroup,
    line - 1, -- 0-indexed
    hl_info.start,
    hl_info['end']
  )
end

---Used to add background highlight to a single line in the menu buffer
---Notice that all other highlight added using this function will be deleted
---@param line integer 1-indexed
---@param hlgroup string? default to 'WinBarMenuCurrentContext'
---@return nil
function winbar_menu_t:hl_line_single(line, hlgroup)
  if not self.buf then
    return
  end
  hlgroup = hlgroup or 'WinBarMenuCurrentContext'
  -- Use namespace to delete highlights conveniently
  local ns = vim.api.nvim_create_namespace('WinBarMenu')
  vim.api.nvim_set_hl(ns, hlgroup, vim.api.nvim_get_hl(0, { name = hlgroup }))
  vim.api.nvim_buf_clear_namespace(self.buf, ns, 0, -1)
  vim.api.nvim_buf_add_highlight(
    self.buf,
    ns,
    hlgroup,
    line - 1, -- 0-indexed
    0,
    -1
  )
end

---Make a buffer for the menu and set buffer-local keymaps
---Must be called after the popup window is created
---Side effect: change self.buf, self.hl_info
---@return nil
function winbar_menu_t:make_buf()
  if self.buf then
    return
  end
  self.buf = vim.api.nvim_create_buf(false, true)
  local lines = {} ---@type string[]
  local hl_info = {} ---@type {start: integer, end: integer, hlgroup: string}[][]
  for _, entry in ipairs(self.entries) do
    local line, entry_hl_info = entry:cat()
    -- Pad the line with spaces to the width of the window
    -- This is to make sure hl-WinBarMenuCurrentContext colors
    -- the entire line
    table.insert(
      lines,
      line
        .. string.rep(
          ' ',
          self._win_configs.width - vim.fn.strdisplaywidth(line)
        )
    )
    table.insert(hl_info, entry_hl_info)
  end
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  for entry_idx, entry_hl_info in ipairs(hl_info) do
    for _, hl in ipairs(entry_hl_info) do
      self:hl_line_range(entry_idx, hl)
    end
    if self.cursor and entry_idx == self.cursor[1] then
      self:hl_line_single(entry_idx)
    end
  end
  vim.bo[self.buf].ma = false
  vim.bo[self.buf].ft = 'winbar_menu'

  -- Set buffer-local keymaps
  vim.keymap.set({ 'x', 'n' }, '<LeftMouse>', function()
    local mouse = vim.fn.getmousepos()
    if mouse.winid ~= self.win then
      local parent_menu = _G.winbar.menus[mouse.winid]
      if parent_menu and parent_menu.sub_menu then
        parent_menu.sub_menu:close()
      end
      if vim.api.nvim_win_is_valid(mouse.winid) then
        vim.api.nvim_set_current_win(mouse.winid)
      end
      return
    end
    self:click_at({ mouse.line, mouse.column })
  end, { buffer = self.buf })
  vim.keymap.set({ 'x', 'n' }, '<CR>', function()
    local cursor = vim.api.nvim_win_get_cursor(self.win)
    local component = self.entries[cursor[1]]:first_clickable(cursor[2])
    if component then
      self:click_on(component)
    end
  end, { buffer = self.buf })

  -- Set buffer-local autocmds
  vim.api.nvim_create_autocmd('WinClosed', {
    group = groupid,
    buffer = self.buf,
    callback = function()
      -- Trigger self:close() when the popup window is closed
      -- to ensure the cursor is set to the correct previous window
      self:close()
    end,
  })
end

---Open the menu
---Side effect: change self.win and self.buf
---@return nil
function winbar_menu_t:open()
  if self.is_open then
    return
  end
  self.is_open = true

  self.prev_win = vim.api.nvim_get_current_win()
  local parent_menu = _G.winbar.menus[self.prev_win]
  if parent_menu then
    parent_menu.sub_menu = self
    self.parent_menu = parent_menu
    self.prev_win = parent_menu.win
  end

  self:eval_win_config()
  self:make_buf()
  self.win = vim.api.nvim_open_win(self.buf, true, self._win_configs)
  vim.wo[self.win].scrolloff = 0
  vim.wo[self.win].sidescrolloff = 0
  _G.winbar.menus[self.win] = self
  -- Initialize cursor position
  if self._win_configs.focusable ~= false and self.cursor then
    vim.api.nvim_win_set_cursor(self.win, self.cursor)
  end
end

---Close the menu
---@return nil
function winbar_menu_t:close()
  if not self.is_open then
    return
  end
  self.is_open = false

  if self.sub_menu then
    self.sub_menu:close()
  end
  if self.win and vim.api.nvim_win_is_valid(self.prev_win) then
    vim.api.nvim_set_current_win(self.prev_win)
  end
  _G.winbar.menus[self.win] = nil
  if vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end
  if self.win then
    self.win = nil
  end
end

---Toggle the menu
---@return nil
function winbar_menu_t:toggle()
  if self.is_open then
    self:close()
  else
    self:open()
  end
end

return {
  winbar_menu_t = winbar_menu_t,
  winbar_menu_entry_t = winbar_menu_entry_t,
}
