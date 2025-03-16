-- Name:         stata
-- Description:  Stata colorscheme, inspired by pygment's stata theme
-- Author:       Bekaboo <kankefengjing@gmail.com>
-- Maintainer:   Bekaboo <kankefengjing@gmail.com>
-- License:      BSD
-- Last Updated: Sun 16 Mar 2025 07:55:22 PM EDT

-- Clear hlgroups and set colors_name {{{
vim.cmd.hi('clear')
vim.g.colors_name = 'stata'
-- }}}

-- Palette {{{
-- stylua: ignore start
local c_whitespace
local c_error
local c_warn
local c_string
local c_number
local c_operator
local c_special
local c_special2
local c_other
local c_keyword
local c_constant
local c_comment
local c_variable
local c_global_variable
local c_generic
local c_background
local c_foreground
local c_highlight
local c_lightgreen
local c_lightblue
local c_lightred
local c_lightyellow

if vim.go.bg == 'dark' then
  c_background      = { '#232629', 235 }
  c_foreground      = { '#cccccc', 251 }
  c_highlight       = { '#383c41', 238 }
  c_whitespace      = { '#bbbbbb', 250 }
  c_error           = { '#c85a5a', 124 }
  c_warn            = { '#dcb571', 179 }
  c_string          = { '#51cc99', 79  }
  c_number          = { '#4FB8CC', 73  }
  c_operator        = { '#cccccc', 251 }
  c_special         = { '#6a6aff', 69  }
  c_special2        = { '#3b9670', 79  }
  c_other           = { '#e2828e', 174 }
  c_keyword         = { '#7686bb', 67  }
  c_constant        = { '#cccccc', 251 }
  c_comment         = { '#777777', 243 }
  c_variable        = { '#7AB4DB', 74  }
  c_global_variable = { '#BE646C', 131 }
  c_generic         = { '#ffffff', 231 }
  c_lightgreen      = { '#64de64', 83  }
  c_lightblue       = { '#bdc9ff', 147 }
  c_lightred        = { '#ff8f96', 210 }
  c_lightyellow     = { '#ffd283', 222 }
else
  c_background      = { '#ffffff', 231 }
  c_foreground      = { '#111111', 233 }
  c_highlight       = { '#f4f5f5', 255 }
  c_whitespace      = { '#e0e2e2', 250 }
  c_error           = { '#bc5555', 124 }
  c_warn            = { '#cba260', 137 }
  c_string          = { '#7a2424', 88  }
  c_number          = { '#2c2cff', 27  }
  c_operator        = { '#111111', 233 }
  c_special         = { '#7373ff', 27  }
  c_special2        = { '#288828', 28  }
  c_other           = { '#be646c', 131 }
  c_keyword         = { '#353580', 60  }
  c_constant        = { '#111111', 233 }
  c_comment         = { '#008800', 28  }
  c_variable        = { '#288c8c', 73  }
  c_global_variable = { '#b5565e', 131 }
  c_generic         = { '#000000', 0   }
  c_lightgreen      = { '#64de64', 83  }
  c_lightblue       = { '#bdc9ff', 147 }
  c_lightred        = { '#ff8f96', 210 }
  c_lightyellow     = { '#ffd283', 222 }
end
-- stylua: ignore end
-- }}}

-- Set terminal colors {{{
-- stylua: ignore start
if vim.go.bg == 'dark' then
  vim.g.terminal_color_0  = c_background[1]
  vim.g.terminal_color_1  = c_error[1]
  vim.g.terminal_color_2  = c_string[1]
  vim.g.terminal_color_3  = c_other[1]
  vim.g.terminal_color_4  = c_variable[1]
  vim.g.terminal_color_5  = c_special[1]
  vim.g.terminal_color_6  = c_keyword[1]
  vim.g.terminal_color_7  = c_foreground[1]
  vim.g.terminal_color_8  = c_comment[1]
  vim.g.terminal_color_9  = c_global_variable[1]
  vim.g.terminal_color_10 = c_string[1]
  vim.g.terminal_color_11 = c_other[1]
  vim.g.terminal_color_12 = c_variable[1]
  vim.g.terminal_color_13 = c_special[1]
  vim.g.terminal_color_14 = c_keyword[1]
  vim.g.terminal_color_15 = c_generic[1]
else
  vim.g.terminal_color_0  = c_background[1]
  vim.g.terminal_color_1  = c_error[1]
  vim.g.terminal_color_2  = c_comment[1]
  vim.g.terminal_color_3  = c_other[1]
  vim.g.terminal_color_4  = c_special[1]
  vim.g.terminal_color_5  = c_keyword[1]
  vim.g.terminal_color_6  = c_variable[1]
  vim.g.terminal_color_7  = c_foreground[1]
  vim.g.terminal_color_8  = c_whitespace[1]
  vim.g.terminal_color_9  = c_global_variable[1]
  vim.g.terminal_color_10 = c_comment[1]
  vim.g.terminal_color_11 = c_other[1]
  vim.g.terminal_color_12 = c_special[1]
  vim.g.terminal_color_13 = c_keyword[1]
  vim.g.terminal_color_14 = c_variable[1]
  vim.g.terminal_color_15 = c_foreground[1]
end
-- stylua: ignore end
-- }}}

-- Highlight groups {{{1
local hlgroups = {
  -- Common {{{2
  ColorColumn = { bg = c_highlight },
  Conceal = { fg = c_foreground },
  CurSearch = { link = 'IncSearch' },
  Cursor = { fg = c_background, bg = c_foreground },
  CursorColumn = { bg = c_highlight },
  CursorIM = { link = 'Cursor' },
  CursorLine = { bg = c_highlight },
  CursorLineNr = { fg = c_foreground, bold = true },
  DebugPC = { bg = c_string },
  DiffAdd = { bg = c_string, fg = c_background },
  DiffChange = { bg = c_variable, fg = c_background },
  DiffDelete = { fg = c_other },
  DiffText = { bg = c_special, fg = c_foreground },
  Directory = { fg = c_string },
  EndOfBuffer = { fg = c_comment },
  ErrorMsg = { fg = c_error },
  FloatBorder = { fg = c_foreground, bg = c_highlight },
  FloatTitle = { fg = c_other, bg = c_highlight, bold = true },
  FoldColumn = { fg = c_comment },
  Folded = { fg = c_comment, bg = c_highlight },
  IncSearch = { bg = c_other, fg = c_background, bold = true },
  LineNr = { fg = c_comment },
  MatchParen = { bg = c_highlight, bold = true },
  ModeMsg = { fg = c_foreground },
  MoreMsg = { fg = c_string },
  NonText = { fg = c_comment },
  Normal = { fg = c_foreground, bg = c_background },
  NormalFloat = { fg = c_foreground, bg = c_highlight },
  NormalNC = { link = 'Normal' },
  Pmenu = { fg = c_foreground, bg = c_highlight },
  PmenuSbar = { bg = c_highlight },
  PmenuSel = { fg = c_foreground, bg = c_special, bold = true },
  PmenuThumb = { bg = c_keyword },
  Question = { fg = c_string },
  QuickFixLine = { link = 'Visual' },
  Search = { bg = c_highlight },
  SignColumn = { fg = c_comment },
  SpecialKey = { fg = c_special },
  SpellBad = { undercurl = true, sp = c_error },
  SpellCap = { link = 'SpellBad' },
  SpellLocal = { link = 'SpellBad' },
  SpellRare = { link = 'SpellBad' },
  StatusLine = { fg = c_foreground, bg = c_special },
  StatusLineNC = { fg = c_background, bg = c_whitespace },
  Substitute = { link = 'Search' },
  TabLine = { fg = c_background, bg = c_constant },
  TabLineFill = { fg = c_background, bg = c_whitespace },
  TabLineSel = { fg = c_foreground, bg = c_special },
  TermCursor = { fg = c_background, bg = c_keyword },
  Title = { fg = c_special, bold = true },
  VertSplit = { fg = c_whitespace, bg = c_whitespace },
  Visual = { bg = c_highlight },
  VisualNOS = { link = 'Visual' },
  WarningMsg = { fg = c_other },
  Whitespace = { link = 'NonText' },
  WildMenu = { link = 'PmenuSel' },
  WinBar = { fg = c_foreground },
  WinBarNC = { fg = c_comment },
  WinSeparator = { link = 'VertSplit' },
  lCursor = { link = 'Cursor' },
  -- }}}2

  -- Syntax {{{2
  Comment = { fg = c_comment, italic = true },
  Constant = { fg = c_constant, bold = true },
  String = { fg = c_string },
  Character = { fg = c_string },
  Number = { fg = c_number },
  Boolean = { fg = c_keyword },
  Float = { link = 'Number' },
  Identifier = { fg = c_variable },
  Function = { fg = c_generic, bold = true },
  Statement = { fg = c_keyword, bold = true },
  Conditional = { fg = c_keyword, bold = true },
  Repeat = { fg = c_keyword, bold = true },
  Label = { fg = c_other },
  Operator = { fg = c_operator },
  Keyword = { fg = c_keyword, bold = true },
  Exception = { fg = c_keyword, bold = true },
  PreProc = { fg = c_keyword },
  Include = { link = 'PreProc' },
  Define = { link = 'PreProc' },
  Macro = { link = 'PreProc' },
  PreCondit = { link = 'PreProc' },
  Type = { fg = c_keyword },
  StorageClass = { link = 'Type' },
  Structure = { link = 'Type' },
  Typedef = { link = 'Type' },
  Special = { fg = c_variable },
  SpecialChar = { link = 'Special' },
  Tag = { fg = c_keyword },
  Delimiter = { fg = c_foreground },
  SpecialComment = { fg = c_comment, bold = true },
  Debug = { fg = c_other },
  Underlined = { underline = true },
  Ignore = { fg = c_comment },
  Error = { fg = c_error, bold = true },
  Todo = { fg = c_background, bg = c_keyword, bold = true },
  -- }}}2

  -- Treesitter syntax {{{2
  ['@variable'] = { link = 'Identifier' },
  ['@variable.builtin'] = { fg = c_variable, bold = true },
  ['@variable.parameter'] = { fg = c_variable },
  ['@variable.member'] = { fg = c_variable },
  ['@constant'] = { link = 'Constant' },
  ['@constant.builtin'] = { fg = c_global_variable },
  ['@constant.macro'] = { link = 'Define' },
  ['@module'] = { fg = c_keyword },
  ['@label'] = { link = 'Label' },
  ['@string'] = { link = 'String' },
  ['@string.escape'] = { fg = c_other },
  ['@string.special'] = { link = 'SpecialChar' },
  ['@character'] = { link = 'Character' },
  ['@character.special'] = { link = 'SpecialChar' },
  ['@boolean'] = { link = 'Boolean' },
  ['@number'] = { link = 'Number' },
  ['@number.float'] = { link = 'Float' },
  ['@function'] = { link = 'Function' },
  ['@function.builtin'] = { link = 'Function' },
  ['@function.call'] = { link = 'Function' },
  ['@function.macro'] = { link = 'Macro' },
  ['@constructor'] = {},
  ['@keyword'] = { link = 'Keyword' },
  ['@keyword.function'] = { link = 'Keyword' },
  ['@keyword.return'] = { link = 'Keyword' },
  ['@keyword.operator'] = { link = 'Operator' },
  ['@operator'] = { link = 'Operator' },
  ['@keyword.import'] = { link = 'Include' },
  ['@type'] = { link = 'Type' },
  ['@type.builtin'] = { link = 'Type' },
  ['@type.definition'] = { link = 'Typedef' },
  ['@type.qualifier'] = { link = 'Type' },
  ['@comment'] = { link = 'Comment' },
  ['@punctuation.delimiter'] = { link = 'Delimiter' },
  ['@punctuation.bracket'] = { fg = c_foreground },
  ['@markup.heading'] = { link = 'Title' },
  ['@markup.raw'] = { link = 'String' },
  ['@markup.link'] = { fg = c_special, underline = true },
  ['@markup.link.url'] = { fg = c_special, underline = true },
  ['@markup.list'] = { fg = c_keyword },
  ['@markup.strong'] = { bold = true },
  ['@markup.emphasis'] = { italic = true },
  ['@markup.strikethrough'] = { strikethrough = true },
  ['@markup.underline'] = { underline = true },
  ['@tag'] = { fg = c_keyword },
  ['@tag.attribute'] = { fg = c_variable },
  ['@tag.delimiter'] = { fg = c_foreground },
  -- }}}2

  -- LSP {{{2
  LspReferenceText = { link = 'Visual' },
  LspReferenceRead = { link = 'LspReferenceText' },
  LspReferenceWrite = { link = 'LspReferenceText' },
  LspSignatureActiveParameter = { link = 'Search' },
  LspInfoBorder = { link = 'FloatBorder' },
  -- }}}2

  -- Diagnostic {{{2
  DiagnosticOk = { fg = c_string },
  DiagnosticError = { fg = c_error },
  DiagnosticWarn = { fg = c_warn },
  DiagnosticInfo = { fg = c_special },
  DiagnosticHint = { fg = c_special },
  DiagnosticVirtualTextOk = { fg = c_string, bg = c_highlight },
  DiagnosticVirtualTextError = { fg = c_error, bg = c_highlight },
  DiagnosticVirtualTextWarn = { fg = c_warn, bg = c_highlight },
  DiagnosticVirtualTextInfo = { fg = c_special, bg = c_highlight },
  DiagnosticVirtualTextHint = { fg = c_special, bg = c_highlight },
  DiagnosticUnderlineOk = { underline = true, sp = c_string },
  DiagnosticUnderlineError = { undercurl = true, sp = c_error },
  DiagnosticUnderlineWarn = { undercurl = true, sp = c_warn },
  DiagnosticUnderlineInfo = { undercurl = true, sp = c_special },
  DiagnosticUnderlineHint = { undercurl = true, sp = c_special },
  DiagnosticFloatingOk = { link = 'DiagnosticOk' },
  DiagnosticFloatingError = { link = 'DiagnosticError' },
  DiagnosticFloatingWarn = { link = 'DiagnosticWarn' },
  DiagnosticFloatingInfo = { link = 'DiagnosticInfo' },
  DiagnosticFloatingHint = { link = 'DiagnosticHint' },
  DiagnosticSignOk = { link = 'DiagnosticOk' },
  DiagnosticSignError = { link = 'DiagnosticError' },
  DiagnosticSignWarn = { link = 'DiagnosticWarn' },
  DiagnosticSignInfo = { link = 'DiagnosticInfo' },
  DiagnosticSignHint = { link = 'DiagnosticHint' },
  DiagnosticUnnecessary = { fg = c_comment, undercurl = true, sp = c_comment },
  -- }}}2

  -- Plugins {{{2
  -- nvim-cmp
  CmpItemAbbrDeprecated = { fg = c_comment, strikethrough = true },
  CmpItemAbbrMatch = { fg = c_other, bold = true },
  CmpItemAbbrMatchFuzzy = { link = 'CmpItemAbbrMatch' },
  CmpItemKindText = { link = 'String' },
  CmpItemKindMethod = { link = 'Function' },
  CmpItemKindFunction = { link = 'Function' },
  CmpItemKindConstructor = { link = 'Function' },
  CmpItemKindField = { fg = c_variable },
  CmpItemKindProperty = { link = 'CmpItemKindField' },
  CmpItemKindVariable = { fg = c_variable, bold = true },
  CmpItemKindReference = { link = 'CmpItemKindVariable' },
  CmpItemKindModule = { fg = c_keyword },
  CmpItemKindEnum = { fg = c_keyword },
  CmpItemKindEnumMember = { link = 'CmpItemKindEnum' },
  CmpItemKindKeyword = { link = 'Keyword' },
  CmpItemKindOperator = { link = 'Operator' },
  CmpItemKindSnippet = { fg = c_string },
  CmpItemKindColor = { fg = c_keyword },
  CmpItemKindConstant = { link = 'Constant' },
  CmpItemKindCopilot = { fg = c_special },
  CmpItemKindValue = { link = 'Number' },
  CmpItemKindClass = { link = 'Type' },
  CmpItemKindStruct = { link = 'Type' },
  CmpItemKind = { fg = c_foreground },
  CmpItemMenu = { link = 'Pmenu' },

  -- GitSigns
  GitSignsAdd = { fg = c_string },
  GitSignsChange = { fg = c_special },
  GitSignsDelete = { fg = c_other },

  -- statusline
  StatusLineHeader = { fg = c_foreground, bg = c_special2 },
  StatusLineHeaderModified = { fg = c_foreground, bg = c_other },
  StatusLineGitChanged = { fg = c_variable },
  StatusLineDiagnosticHint = { fg = c_lightblue },
  StatusLineDiagnosticWarn = { fg = c_lightyellow },
  StatusLineDiagnosticError = { fg = c_lightred },
  -- }}}2
}
-- }}}1

-- Highlight group overrides {{{1
if vim.go.bg == 'light' then
  hlgroups.Visual = { bg = c_whitespace }
  hlgroups.LineNr = { fg = c_foreground }
  hlgroups.NonText = { fg = c_foreground }
  hlgroups.TabLine = { fg = c_foreground, bg = c_highlight }
  hlgroups.DiffAdd = { bg = c_special2, fg = c_background }
  hlgroups.DiffChange = { bg = c_keyword, fg = c_background }
  hlgroups.DiffText = { bg = c_special, fg = c_background }
  hlgroups.GitSignsAdd = { fg = c_special2 }
  hlgroups.StatusLine = { fg = c_background, bg = c_special }
  hlgroups.StatusLineNC = { fg = c_foreground, bg = c_whitespace }
  hlgroups.StatusLineHeader = { fg = c_background, bg = c_special2 }
  hlgroups.StatusLineHeaderModified = { fg = c_background, bg = c_error }
  hlgroups.StatusLineGitAdded = { fg = c_lightgreen }
  hlgroups.StatusLineGitChanged = { fg = c_lightblue }
  hlgroups.StatusLineGitRemoved = { fg = c_lightred }
end
-- }}}1

-- Set highlight groups {{{1
for name, attr in pairs(hlgroups) do
  attr.ctermbg = attr.bg and attr.bg[2]
  attr.ctermfg = attr.fg and attr.fg[2]
  attr.bg = attr.bg and attr.bg[1]
  attr.fg = attr.fg and attr.fg[1]
  attr.sp = attr.sp and attr.sp[1]
  vim.api.nvim_set_hl(0, name, attr)
end
-- }}}1

-- vim:ts=2:sw=2:sts=2:fdm=marker
