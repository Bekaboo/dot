--stylua: ignore start
local hlgroups = {
  WinBarCurrentContext            = { link = 'Visual' },
  WinBarHover                     = { link = 'Visual' },
  WinBarIconKindDefault           = { link = 'Special' },
  WinBarIconKindArray             = { link = 'Operator' },
  WinBarIconKindBoolean           = { link = 'Boolean' },
  WinBarIconKindBreakStatement    = { link = 'Error' },
  WinBarIconKindCall              = { link = 'Function' },
  WinBarIconKindCaseStatement     = { link = 'Conditional' },
  WinBarIconKindClass             = { link = 'Type' },
  WinBarIconKindConstant          = { link = 'Constant' },
  WinBarIconKindConstructor       = { link = '@constructor' },
  WinBarIconKindContinueStatement = { link = 'Repeat' },
  WinBarIconKindDeclaration       = { link = 'WinBarIconKindDefault' },
  WinBarIconKindDelete            = { link = 'Error' },
  WinBarIconKindDoStatement       = { link = 'Repeat' },
  WinBarIconKindElseStatement     = { link = 'Conditional' },
  WinBarIconKindElement           = { link = 'WinBarIconKindDefault' },
  WinBarIconKindEnum              = { link = 'Constant' },
  WinBarIconKindEnumMember        = { link = 'WinBarIconKindEnumMember' },
  WinBarIconKindEvent             = { link = '@lsp.type.event' },
  WinBarIconKindField             = { link = 'WinBarIconKindDefault' },
  WinBarIconKindFile              = { link = 'WinBarIconKindFolder' },
  WinBarIconKindFolder            = { link = 'Directory' },
  WinBarIconKindForStatement      = { link = 'Repeat' },
  WinBarIconKindFunction          = { link = 'Function' },
  WinBarIconKindH1Marker          = { link = 'markdownH1' },
  WinBarIconKindH2Marker          = { link = 'markdownH2' },
  WinBarIconKindH3Marker          = { link = 'markdownH3' },
  WinBarIconKindH4Marker          = { link = 'markdownH4' },
  WinBarIconKindH5Marker          = { link = 'markdownH5' },
  WinBarIconKindH6Marker          = { link = 'markdownH6' },
  WinBarIconKindIdentifier        = { link = 'WinBarIconKindDefault' },
  WinBarIconKindIfStatement       = { link = 'Conditional' },
  WinBarIconKindInterface         = { link = 'Type' },
  WinBarIconKindKeyword           = { link = '@keyword' },
  WinBarIconKindList              = { link = 'Operator' },
  WinBarIconKindMacro             = { link = 'Macro' },
  WinBarIconKindMarkdownH1        = { link = 'markdownH1' },
  WinBarIconKindMarkdownH2        = { link = 'markdownH2' },
  WinBarIconKindMarkdownH3        = { link = 'markdownH3' },
  WinBarIconKindMarkdownH4        = { link = 'markdownH4' },
  WinBarIconKindMarkdownH5        = { link = 'markdownH5' },
  WinBarIconKindMarkdownH6        = { link = 'markdownH6' },
  WinBarIconKindMethod            = { link = 'Function' },
  WinBarIconKindModule            = { link = '@module' },
  WinBarIconKindNamespace         = { link = '@lsp.type.namespace' },
  WinBarIconKindNull              = { link = 'Constant' },
  WinBarIconKindNumber            = { link = 'Number' },
  WinBarIconKindObject            = { link = 'Statement' },
  WinBarIconKindOperator          = { link = 'Operator' },
  WinBarIconKindPackage           = { link = '@module' },
  WinBarIconKindPair              = { link = 'WinBarIconKindDefault' },
  WinBarIconKindProperty          = { link = 'WinBarIconKindDefault' },
  WinBarIconKindReference         = { link = 'WinBarIconKindDefault' },
  WinBarIconKindRepeat            = { link = 'Repeat' },
  WinBarIconKindRuleSet           = { link = '@lsp.type.namespace' },
  WinBarIconKindScope             = { link = '@lsp.type.namespace' },
  WinBarIconKindSpecifier         = { link = '@keyword' },
  WinBarIconKindStatement         = { link = 'Statement' },
  WinBarIconKindString            = { link = '@string' },
  WinBarIconKindStruct            = { link = 'Type' },
  WinBarIconKindSwitchStatement   = { link = 'Conditional' },
  WinBarIconKindType              = { link = 'Type' },
  WinBarIconKindTypeParameter     = { link = 'WinBarIconKindDefault' },
  WinBarIconKindUnit              = { link = 'WinBarIconKindDefault' },
  WinBarIconKindValue             = { link = 'Number' },
  WinBarIconKindVariable          = { link = 'WinBarIconKindDefault' },
  WinBarIconKindWhileStatement    = { link = 'Repeat' },
  WinBarIconUIIndicator           = { link = 'SpecialChar' },
  WinBarIconUIPickPivot           = { link = 'Error' },
  WinBarIconUISeparator           = { link = 'Comment' },
  WinBarIconUISeparatorMenu       = { link = 'WinBarIconUISeparator' },
  WinBarMenuCurrentContext        = { link = 'PmenuSel' },
  WinBarMenuFloatBorder           = { link = 'FloatBorder' },
  WinBarMenuHoverEntry            = { link = 'IncSearch' },
  WinBarMenuHoverIcon             = { reverse = true },
  WinBarMenuHoverSymbol           = { bold = true },
  WinBarMenuNormalFloat           = { link = 'NormalFloat' },
  WinBarMenuSbar                  = { link = 'PmenuSbar' },
  WinBarMenuThumb                 = { link = 'PmenuThumb' },
  WinBarPreview                   = { link = 'Visual' },
}
--stylua: ignore end

---Set WinBar & WinBarNC background to Normal background
---@return nil
local function clear_winbar_bg()
  ---@param name string
  ---@return nil
  local function _clear_bg(name)
    local hl = require('utils.hl').get(0, {
      name = name,
      winhl_link = false,
    })
    if hl.bg or hl.ctermbg then
      hl.bg = nil
      hl.ctermbg = nil
      vim.api.nvim_set_hl(0, name, hl)
    end
  end

  _clear_bg('WinBar')
  _clear_bg('WinBarNC')
end

---Set winbar highlight groups
---@return nil
local function set_hlgroups()
  for hl_name, hl_settings in pairs(hlgroups) do
    hl_settings.default = true
    vim.api.nvim_set_hl(0, hl_name, hl_settings)
  end
end

---Initialize highlight groups for winbar
local function init()
  set_hlgroups()
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = vim.api.nvim_create_augroup('WinBarHlGroups', {}),
    callback = set_hlgroups,
  })

  clear_winbar_bg()
  local gid_clear_bg = vim.api.nvim_create_augroup('WinBarHlClearBg', {})
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = gid_clear_bg,
    callback = clear_winbar_bg,
  })
  vim.api.nvim_create_autocmd('OptionSet', {
    group = gid_clear_bg,
    pattern = 'background',
    callback = clear_winbar_bg,
  })
end

return {
  init = init,
}
