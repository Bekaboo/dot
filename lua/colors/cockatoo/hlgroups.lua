package.loaded['colors.cockatoo.palette'] = nil
local plt = require('colors.cockatoo.palette')

-- stylua: ignore start
return {
  -- Common highlight groups
  Normal             = { fg = plt.smoke, bg = plt.jeans },
  NormalFloat        = { fg = plt.smoke, bg = plt.ocean },
  NormalNC           = { link = 'Normal' },
  ColorColumn        = { bg = plt.deepsea },
  Conceal            = { fg = plt.smoke },
  Cursor             = { fg = plt.space, bg = plt.white },
  CursorColumn       = { bg = plt.ocean },
  CursorIM           = { fg = plt.space, bg = plt.flashlight },
  CursorLine         = { bg = plt.ocean },
  CursorLineNr       = { fg = plt.orange, bold = true },
  DebugPC            = { bg = plt.purple_blend },
  lCursor            = { link = 'Cursor' },
  TermCursor         = { fg = plt.space, bg = plt.orange },
  TermCursorNC       = { fg = plt.orange, bg = plt.ocean },
  DiffAdd            = { bg = plt.aqua_blend },
  DiffAdded          = { fg = plt.tea, bg = plt.aqua_blend },
  DiffChange         = { bg = plt.purple_blend },
  DiffDelete         = { fg = plt.wine, bg = plt.wine_blend },
  DiffRemoved        = { fg = plt.scarlet, bg = plt.wine_blend },
  DiffText           = { bg = plt.lavender_blend },
  Directory          = { fg = plt.pigeon },
  EndOfBuffer        = { fg = plt.iron },
  ErrorMsg           = { fg = plt.scarlet },
  FoldColumn         = { fg = plt.steel },
  Folded             = { fg = plt.steel, bg = plt.ocean },
  FloatBorder        = { fg = plt.smoke, bg = plt.ocean },
  FloatShadow        = { bg = plt.shadow, blend = 70 },
  FloatShadowThrough = { bg = plt.shadow, blend = 100 },
  HealthSuccess      = { fg = plt.tea },
  Search             = { fg = plt.flashlight, bg = plt.thunder, bold = true },
  IncSearch          = { fg = plt.black, bg = plt.flashlight, bold = true },
  LineNr             = { fg = plt.steel },
  ModeMsg            = { fg = plt.smoke },
  MoreMsg            = { fg = plt.aqua },
  MsgArea            = { link = 'Normal' },
  MsgSeparator       = { link = 'StatusLine' },
  MatchParen         = { bg = plt.thunder, bold = true },
  NonText            = { fg = plt.iron },
  Pmenu              = { fg = plt.smoke, bg = plt.ocean },
  PmenuSbar          = { bg = plt.deepsea },
  PmenuSel           = { fg = plt.white, bg = plt.thunder },
  PmenuThumb         = { bg = plt.orange },
  Question           = { fg = plt.smoke },
  QuickFixLine       = { link = 'Visual' },
  SignColumn         = { fg = plt.smoke },
  SpecialKey         = { fg = plt.orange },
  SpellBad           = { underdotted = true },
  SpellCap           = { link = 'SpellBad' },
  SpellLocal         = { link = 'SpellBad' },
  SpellRare          = { link = 'SpellBad' },
  StatusLine         = { bg = plt.deepsea },
  StatusLineNC       = { bg = plt.space },
  Substitute         = { link = 'Search' },
  TabLine            = { link = 'StatusLine' },
  TabLineFill        = { fg = plt.pigeon, bg = plt.ocean },
  Title              = { fg = plt.pigeon, bold = true },
  VertSplit          = { fg = plt.deepsea },
  Visual             = { bg = plt.deepsea },
  VisualNOS          = { link = 'Visual' },
  WarningMsg         = { fg = plt.yellow },
  Whitespace         = { link = 'NonText' },
  WildMenu           = { link = 'PmenuSel' },
  Winseparator       = { link = 'VertSplit' },
  WinBar             = { fg = plt.smoke },
  WinBarNC           = { fg = plt.pigeon },

  -- Syntax highlighting
  Comment           = { fg = plt.steel, italic = true },
  Constant          = { fg = plt.ochre },
  String            = { fg = plt.turquoise },
  DocumentKeyword   = { fg = plt.tea },
  Character         = { fg = plt.orange },
  Number            = { fg = plt.purple },
  Boolean           = { fg = plt.ochre },
  Array             = { fg = plt.orange },
  Float             = { link = 'Number' },
  Identifier        = { fg = plt.smoke },
  Builtin           = { fg = plt.pink, italic = true },
  Field             = { fg = plt.pigeon },
  Enum              = { fg = plt.ochre },
  Namespace         = { fg = plt.ochre },
  Parameter         = { fg = plt.smoke },
  Function          = { fg = plt.yellow },
  Statement         = { fg = plt.lavender },
  Specifier         = { fg = plt.lavender },
  Object            = { fg = plt.lavender },
  Conditional       = { fg = plt.magenta },
  Repeat            = { fg = plt.magenta },
  Label             = { fg = plt.magenta },
  Operator          = { fg = plt.orange },
  Keyword           = { fg = plt.cerulean },
  Exception         = { fg = plt.magenta },
  PreProc           = { fg = plt.turquoise },
  PreCondit         = { link = 'PreProc' },
  Include           = { link = 'PreProc' },
  Define            = { link = 'PreProc' },
  Macro             = { fg = plt.ochre },
  Type              = { fg = plt.lavender },
  StorageClass      = { link = 'Keyword' },
  Structure         = { link = 'Type' },
  Typedef           = { fg = plt.beige },
  Special           = { fg = plt.orange },
  SpecialChar       = { link = 'Special' },
  Tag               = { fg = plt.flashlight, underline = true },
  Delimiter         = { fg = plt.orange },
  Bracket           = { fg = plt.cumulonimbus },
  SpecialComment    = { link = 'SpecialChar' },
  Debug             = { link = 'Special' },
  Underlined        = { underline = true },
  Ignore            = { fg = plt.iron },
  Error             = { fg = plt.scarlet },
  Todo              = { fg = plt.black, bg = plt.beige, bold = true },

  -- LSP Highlighting
  LspReferenceText            = { link = 'Identifier' },
  LspReferenceRead            = { link = 'LspReferenceText' },
  LspReferenceWrite           = { link = 'LspReferenceText' },
  LspSignatureActiveParameter = { link = 'IncSearch' },
  LspInfoBorder               = { link = 'FloatBorder' },

  -- Diagnostic highlighting
  DiagnosticOK               = { fg = plt.tea },
  DiagnosticError            = { fg = plt.wine },
  DiagnosticWarn             = { fg = plt.earth },
  DiagnosticInfo             = { fg = plt.smoke },
  DiagnosticHint             = { fg = plt.pigeon },
  DiagnosticVirtualTextOK    = { fg = plt.tea, bg = plt.tea_blend },
  DiagnosticVirtualTextError = { fg = plt.wine, bg = plt.wine_blend },
  DiagnosticVirtualTextWarn  = { fg = plt.earth, bg = plt.earth_blend },
  DiagnosticVirtualTextInfo  = { fg = plt.smoke, bg = plt.smoke_blend },
  DiagnosticVirtualTextHint  = { fg = plt.pigeon, bg = plt.pigeon_blend },
  DiagnosticUnderlineOK      = { underline = true, sp = plt.tea },
  DiagnosticUnderlineError   = { undercurl = true, sp = plt.wine },
  DiagnosticUnderlineWarn    = { undercurl = true, sp = plt.earth },
  DiagnosticUnderlineInfo    = { undercurl = true, sp = plt.flashlight },
  DiagnosticUnderlineHint    = { undercurl = true, sp = plt.pigeon },
  DiagnosticFloatingOK       = { link = 'DiagnosticOK' },
  DiagnosticFloatingError    = { link = 'DiagnosticError' },
  DiagnosticFloatingWarn     = { link = 'DiagnosticWarn' },
  DiagnosticFloatingInfo     = { link = 'DiagnosticInfo' },
  DiagnosticFloatingHint     = { link = 'DiagnosticHint' },
  DiagnosticSignOK           = { link = 'DiagnosticOK' },
  DiagnosticSignError        = { link = 'DiagnosticError' },
  DiagnosticSignWarn         = { link = 'DiagnosticWarn' },
  DiagnosticSignInfo         = { link = 'DiagnosticInfo' },
  DiagnosticSignHint         = { link = 'DiagnosticHint' },

  ['@field']                 = { link = 'Field' },
  ['@property']              = { link = 'Field' },
  ['@annotation']            = { link = 'Operator' },
  ['@comment']               = { link = 'Comment' },
  ['@none']                  = { link = 'None' },
  ['@preproc']               = { link = 'PreProc' },
  ['@define']                = { link = 'Define' },
  ['@operator']              = { link = 'Operator' },
  ['@punctuation.delimiter'] = { link = 'Delimiter' },
  ['@punctuation.bracket']   = { link = 'Bracket' },
  ['@punctuation.special']   = { link = 'Delimiter' },
  ['@string']                = { link = 'String' },
  ['@string.regex']          = { link = 'String' },
  ['@string.escape']         = { link = 'SpecialChar' },
  ['@string.special']        = { link = 'SpecialChar' },
  ['@character']             = { link = 'Character' },
  ['@character.special']     = { link = 'SpecialChar' },
  ['@boolean']               = { link = 'Boolean' },
  ['@number']                = { link = 'Number' },
  ['@float']                 = { link = 'Float' },
  ['@function']              = { link = 'Function' },
  ['@function.call']         = { link = 'Function' },
  ['@function.builtin']      = { link = 'Special' },
  ['@function.macro']        = { link = 'Macro' },
  ['@method']                = { link = 'Function' },
  ['@method.call']           = { link = 'Function' },
  ['@constructor']           = { link = 'Function' },
  ['@parameter']             = { link = 'Parameter' },
  ['@keyword']               = { link = 'Keyword' },
  ['@keyword.function']      = { link = 'Keyword' },
  ['@keyword.return']        = { link = 'Keyword' },
  ['@conditional']           = { link = 'Conditional' },
  ['@repeat']                = { link = 'Repeat' },
  ['@debug']                 = { link = 'Debug' },
  ['@label']                 = { link = 'Keyword' },
  ['@include']               = { link = 'Include' },
  ['@exception']             = { link = 'Exception' },
  ['@type']                  = { link = 'Type' },
  ['@type.Builtin']          = { link = 'Type' },
  ['@type.qualifier']        = { link = 'Type' },
  ['@type.definition']       = { link = 'Typedef' },
  ['@storageclass']          = { link = 'StorageClass' },
  ['@attribute']             = { link = 'Label' },
  ['@variable']              = { link = 'Identifier' },
  ['@variable.Builtin']      = { link = 'Builtin' },
  ['@constant']              = { link = 'Constant' },
  ['@constant.Builtin']      = { link = 'Constant' },
  ['@constant.macro']        = { link = 'Macro' },
  ['@namespace']             = { link = 'Namespace' },
  ['@symbol']                = { link = 'Identifier' },
  ['@text']                  = { link = 'String' },
  ['@text.title']            = { link = 'Title' },
  ['@text.literal']          = { link = 'String' },
  ['@text.uri']              = { link = 'htmlLink' },
  ['@text.math']             = { link = 'Special' },
  ['@text.environment']      = { link = 'Macro' },
  ['@text.environment.name'] = { link = 'Type' },
  ['@text.reference']        = { link = 'Constant' },
  ['@text.todo']             = { link = 'Todo' },
  ['@text.todo.unchecked']   = { link = 'Todo' },
  ['@text.todo.checked']     = { link = 'Done' },
  ['@text.note']             = { link = 'SpecialComment' },
  ['@text.warning']          = { link = 'WarningMsg' },
  ['@text.danger']           = { link = 'ErrorMsg' },
  ['@text.diff.add']         = { link = 'DiffAdded' },
  ['@text.diff.delete']      = { link = 'DiffRemoved' },
  ['@tag']                   = { link = 'Tag' },
  ['@tag.attribute']         = { link = 'Identifier' },
  ['@tag.delimiter']         = { link = 'Delimiter' },
  ['@text.strong']           = { bold = true },
  ['@text.strike']           = { strikethrough = true },
  ['@text.emphasis']         = { fg = plt.black, bg = plt.beige, bold = true, italic = true },
  ['@text.underline']        = { underline = true },
  ['@keyword.operator']      = { link = 'Operator' },

  ['@lsp.type.enum']                       = { link = 'Type' },
  ['@lsp.type.type']                       = { link = 'Type' },
  ['@lsp.type.class']                      = { link = 'Structure' },
  ['@lsp.type.struct']                     = { link = 'Structure' },
  ['@lsp.type.macro']                      = { link = 'Macro' },
  ['@lsp.type.method']                     = { link = 'Function' },
  ['@lsp.type.comment']                    = { link = 'Comment' },
  ['@lsp.type.function']                   = { link = 'Function' },
  ['@lsp.type.property']                   = { link = 'Field' },
  ['@lsp.type.variable']                   = { link = 'Variable' },
  ['@lsp.type.decorator']                  = { link = 'Label' },
  ['@lsp.type.interface']                  = { link = 'Structure' },
  ['@lsp.type.namespace']                  = { link = 'Namespace' },
  ['@lsp.type.parameter']                  = { link = 'Parameter' },
  ['@lsp.type.enumMember']                 = { link = 'Enum' },
  ['@lsp.type.typeParameter']              = { link = 'Parameter' },
  ['@lsp.typemod.keyword.documentation']   = { link = 'DocumentKeyword' },
  ['@lsp.typemod.function.defaultLibrary'] = { link = 'Special' },
  ['@lsp.typemod.variable.defaultLibrary'] = { link = 'Builtin' },
  ['@lsp.typemod.variable.global']         = { link = 'Identifier' },

  -- HTML
  htmlArg            = { fg = plt.pigeon },
  htmlBold           = { bold = true },
  htmlBoldItalic     = { bold = true, italic = true },
  htmlTag            = { fg = plt.smoke },
  htmlTagName        = { link = 'Tag' },
  htmlSpecialTagName = { fg = plt.yellow },
  htmlEndTag         = { fg = plt.yellow },
  htmlH1             = { fg = plt.yellow, bold = true },
  htmlH2             = { fg = plt.ochre, bold = true },
  htmlH3             = { fg = plt.pink, bold = true },
  htmlH4             = { fg = plt.lavender, bold = true },
  htmlH5             = { fg = plt.cerulean, bold = true },
  htmlH6             = { fg = plt.aqua, bold = true },
  htmlItalic         = { italic = true },
  htmlLink           = { fg = plt.flashlight, underline = true },
  htmlSpecialChar    = { fg = plt.beige },
  htmlTitle          = { fg = plt.pigeon },
  -- Json
  jsonKeyword        = { link = 'Keyword' },
  jsonBraces         = { fg = plt.smoke },
  -- Markdown
  markdownBold       = { fg = plt.aqua, bold = true },
  markdownBoldItalic = { fg = plt.skyblue, bold = true, italic = true },
  markdownCode       = { fg = plt.pigeon },
  markdownError      = { link = 'None' },
  markdownEscape     = { link = 'None' },
  markdownListMarker = { fg = plt.orange },
  markdownH1         = { link = 'htmlH1' },
  markdownH2         = { link = 'htmlH2' },
  markdownH3         = { link = 'htmlH3' },
  markdownH4         = { link = 'htmlH4' },
  markdownH5         = { link = 'htmlH5' },
  markdownH6         = { link = 'htmlH6' },
  -- Shell
  shDeref            = { link = 'Macro' },
  shDerefVar         = { link = 'Macro' },
  -- Git
  gitHash            = { fg = plt.pigeon },
  -- Checkhealth
  helpHeader         = { fg = plt.pigeon, bold = true },
  helpSectionDelim   = { fg = plt.ochre, bold = true },
  helpCommand        = { fg = plt.turquoise },
  helpBacktick       = { fg = plt.turquoise },
  -- Man
  manBold            = { fg = plt.ochre, bold = true },
  manItalic          = { fg = plt.turquoise, italic = true },
  manOptionDesc      = { fg = plt.ochre },
  manReference       = { link = 'htmlLink' },
  manSectionHeading  = { link = 'manBold' },
  manUnderline       = { fg = plt.cerulean, italic = true },


  -- Plugin highlights
  -- nvim-cmp
  CmpItemAbbr            = { fg = plt.smoke },
  CmpItemAbbrDeprecated  = { strikethrough = true },
  CmpItemAbbrMatch       = { fg = plt.white, bold = true },
  CmpItemAbbrMatchFuzzy  = { link = 'CmpItemAbbrMatch' },
  CmpItemKindText        = { link = 'String' },
  CmpItemKindMethod      = { link = 'Function' },
  CmpItemKindFunction    = { link = 'Function' },
  CmpItemKindConstructor = { link = 'Function' },
  CmpItemKindField       = { fg = plt.purple },
  CmpItemKindProperty    = { link = 'CmpItemKindField' },
  CmpItemKindVariable    = { fg = plt.aqua },
  CmpItemKindReference   = { link = 'CmpItemKindVariable' },
  CmpItemKindModule      = { fg = plt.magenta },
  CmpItemKindEnum        = { fg = plt.ochre },
  CmpItemKindEnumMember  = { link = 'CmpItemKindEnum' },
  CmpItemKindKeyword     = { link = 'Keyword' },
  CmpItemKindOperator    = { link = 'Operator' },
  CmpItemKindSnippet     = { fg = plt.tea },
  CmpItemKindColor       = { fg = plt.pink },
  CmpItemKindConstant    = { link = 'Constant' },
  CmpItemKindCopilot     = { fg = plt.magenta },
  CmpItemKindValue       = { link = 'Number' },
  CmpItemKindClass       = { link = 'Type' },
  CmpItemKindStruct      = { link = 'Type' },
  CmpItemKindEvent       = { fg = plt.flashlight },
  CmpItemKindInterface   = { fg = plt.flashlight },
  CmpItemKindFile        = { fg = plt.smoke },
  CmpItemKindFolder      = { fg = plt.pigeon },
  CmpItemKindUnit        = { fg = plt.cerulean },
  CmpItemKind            = { fg = plt.smoke },
  CmpItemMenu            = { fg = plt.smoke },

  -- gitsigns
  GitSignsAdd                      = { fg = plt.tea_blend },
  GitSignsAddInline                = { fg = plt.tea, bg = plt.tea_blend },
  GitSignsAddLnInline              = { fg = plt.tea, bg = plt.tea_blend },
  GitSignsAddPreview               = { link = 'DiffAdded' },
  GitSignsChange                   = { fg = plt.lavender_blend },
  GitSignsChangeInline             = { fg = plt.lavender, bg = plt.lavender_blend },
  GitSignsChangeLnInline           = { fg = plt.lavender, bg = plt.lavender_blend },
  GitSignsCurrentLineBlame         = { fg = plt.smoke, bg = plt.smoke_blend },
  GitSignsDelete                   = { fg = plt.wine },
  GitSignsDeleteInline             = { fg = plt.scarlet, bg = plt.scarlet_blend },
  GitSignsDeleteLnInline           = { fg = plt.scarlet, bg = plt.scarlet_blend },
  GitSignsDeletePreview            = { fg = plt.scarlet, bg = plt.wine_blend },
  GitSignsDeleteVirtLnInLine       = { fg = plt.scarlet, bg = plt.scarlet_blend },
  GitSignsUntracked                = { fg = plt.scarlet_blend },
  GitSignsUntrackedLn              = { bg = plt.scarlet_blend },
  GitSignsUntrackedNr              = { fg = plt.pink },

  -- fugitive
  fugitiveHash              = { link = 'gitHash' },
  fugitiveHeader            = { link = 'Title' },
  fugitiveHeading           = { fg = plt.orange, bold = true },
  fugitiveHelpTag           = { fg = plt.orange },
  fugitiveSymbolicRef       = { fg = plt.yellow },
  fugitiveStagedModifier    = { fg = plt.tea, bold = true },
  fugitiveUnstagedModifier  = { fg = plt.scarlet, bold = true },
  fugitiveUntrackedModifier = { fg = plt.pigeon, bold = true },
  fugitiveStagedHeading     = { fg = plt.aqua, bold = true },
  fugitiveUnstagedHeading   = { fg = plt.ochre, bold = true },
  fugitiveUntrackedHeading  = { fg = plt.lavender, bold = true },

  -- telescope
  TelescopeNormal               = { link = 'NormalFloat' },
  TelescopePromptNormal         = { bg = plt.deepsea },
  TelescopeTitle                = { fg = plt.space, bg = plt.turquoise, bold = true },
  TelescopePromptTitle          = { fg = plt.space, bg = plt.yellow, bold = true },
  TelescopeBorder               = { fg = plt.smoke, bg = plt.ocean },
  TelescopePromptBorder         = { fg = plt.smoke, bg = plt.deepsea },
  TelescopeSelection            = { bg = plt.thunder },
  TelescopeMultiSelection       = { bg = plt.thunder, bold = true },
  TelescopePreviewLine          = { bg = plt.thunder },
  TelescopeMatching             = { link = 'Search' },
  TelescopePromptCounter        = { link = 'Comment' },
  TelescopePromptPrefix         = { fg = plt.orange },
  TelescopeSelectionCaret       = { fg = plt.orange, bg = plt.thunder },

  -- aerial
  AerialLine              = { fg = plt.white, bg = plt.thunder, bold = true },
  AerialArrayIcon         = { link = 'Array' },
  AerialBooleanIcon       = { link = 'Boolean' },
  AerialClassIcon         = { link = 'CmpItemKindClass' },
  AerialConstantIcon      = { link = 'CmpItemKindConstant' },
  AerialConstructorIcon   = { link = 'CmpItemKindConstructor' },
  AerialEnumIcon          = { link = 'CmpItemKindEnum' },
  AerialEnumMemberIcon    = { link = 'CmpItemKindEnumMember' },
  AerialEventIcon         = { link = 'CmpItemKindEvent' },
  AerialFieldIcon         = { link = 'CmpItemKindField' },
  AerialFileIcon          = { link = 'CmpItemKindFile' },
  AerialFunctionIcon      = { link = 'CmpItemKindFunction' },
  AerialGuide             = { link = 'Comment' },
  AerialInterfaceIcon     = { link = 'CmpItemKindInterface' },
  AerialKeyIcon           = { link = 'CmpItemKindKeyword' },
  AerialMethodIcon        = { link = 'CmpItemKindMethod' },
  AerialModuleIcon        = { link = 'CmpItemKindModule' },
  AerialNamespaceIcon     = { link = '@namespace' },
  AerialNullIcon          = { link = 'Boolean' },
  AerialNumberIcon        = { link = 'CmpItemKindValue' },
  AerialObjectIcon        = { link = 'Object' },
  AerialOperatorIcon      = { link = 'CmpItemKindOperator' },
  AerialPackageIcon       = { link = 'CmpItemKindModule' },
  AerialPropertyIcon      = { link = 'CmpItemKindProperty' },
  AerialStringIcon        = { link = 'CmpItemKindText' },
  AerialStructIcon        = { link = 'CmpItemKindStruct' },
  AerialTypeParameterIcon = { link = 'CmpItemKind' },
  AerialVariableIcon      = { link = 'CmpItemKindVariable' },

  -- fidget
  FidgetTitle = { link = 'Title' },
  FidgetTask  = { fg = plt.pigeon },

  -- nvim-dap-ui
  DapUIBreakpointsCurrentLine = { link = 'CursorLineNr' },
  DapUIBreakpointsInfo        = { fg = plt.tea },
  DapUIBreakpointsPath        = { link = 'Directory' },
  DapUICurrentFrameName       = { fg = plt.tea, bold = true },
  DapUIDecoration             = { fg = plt.yellow },
  DapUIFloatBorder            = { link = 'FloatBorder' },
  DapUINormalFloat            = { link = 'NormalFloat' },
  DapUILineNumber             = { link = 'LineNr' },
  DapUIModifiedValue          = { fg = plt.skyblue, bold = true },
  DapUIPlayPause              = { fg = plt.tea },
  DapUIPlayPauseNC            = { fg = plt.tea },
  DapUIRestart                = { fg = plt.tea },
  DapUIRestartNC              = { fg = plt.tea },
  DapUIScope                  = { fg = plt.orange },
  DapUISource                 = { link = 'Directory' },
  DapUIStepBack               = { fg = plt.lavender },
  DapUIStepBackRC             = { fg = plt.lavender },
  DapUIStepInto               = { fg = plt.lavender },
  DapUIStepIntoRC             = { fg = plt.lavender },
  DapUIStepOut                = { fg = plt.lavender },
  DapUIStepOutRC              = { fg = plt.lavender },
  DapUIStepOver               = { fg = plt.lavender },
  DapUIStepOverRC             = { fg = plt.lavender },
  DapUIStop                   = { fg = plt.scarlet },
  DapUIStopNC                 = { fg = plt.scarlet },
  DapUIStoppedThread          = { fg = plt.tea },
  DapUIThread                 = { fg = plt.aqua },
  DapUIType                   = { link = 'Type' },
  DapUIVariable               = { link = 'Identifier' },
  DapUIWatchesEmpty           = { link = 'Comment' },
  DapUIWatchesError           = { link = 'Error' },
  DapUIWatchesValue           = { fg = plt.orange },

  -- vimtex
  texArg                = { fg = plt.pigeon },
  texArgNew             = { fg = plt.skyblue },
  texCmd                = { fg = plt.yellow },
  texCmdBib             = { link = 'texCmd' },
  texCmdClass           = { link = 'texCmd' },
  texCmdDef             = { link = 'texCmd' },
  texCmdE3              = { link = 'texCmd' },
  texCmdEnv             = { link = 'texCmd' },
  texCmdEnvM            = { link = 'texCmd' },
  texCmdError           = { link = 'ErrorMsg' },
  texCmdFatal           = { link = 'ErrorMsg' },
  texCmdGreek           = { link = 'texCmd' },
  texCmdInput           = { link = 'texCmd' },
  texCmdItem            = { link = 'texCmd' },
  texCmdLet             = { link = 'texCmd' },
  texCmdMath            = { link = 'texCmd' },
  texCmdNew             = { link = 'texCmd' },
  texCmdPart            = { link = 'texCmd' },
  texCmdRef             = { link = 'texCmd' },
  texCmdSize            = { link = 'texCmd' },
  texCmdStyle           = { link = 'texCmd' },
  texCmdTitle           = { link = 'texCmd' },
  texCmdTodo            = { link = 'texCmd' },
  texCmdType            = { link = 'texCmd' },
  texCmdVerb            = { link = 'texCmd' },
  texComment            = { link = 'Comment' },
  texDefParm            = { link = 'Keyword' },
  texDelim              = { fg = plt.pigeon },
  texE3Cmd              = { link = 'texCmd' },
  texE3Delim            = { link = 'texDelim' },
  texE3Opt              = { link = 'texOpt' },
  texE3Parm             = { link = 'texParm' },
  texE3Type             = { link = 'texCmd' },
  texEnvOpt             = { link = 'texOpt' },
  texError              = { link = 'ErrorMsg' },
  texFileArg            = { link = 'Directory' },
  texFileOpt            = { link = 'texOpt' },
  texFilesArg           = { link = 'texFileArg' },
  texFilesOpt           = { link = 'texFileOpt' },
  texLength             = { fg = plt.lavender },
  texLigature           = { fg = plt.pigeon },
  texOpt                = { fg = plt.smoke },
  texOptEqual           = { fg = plt.orange },
  texOptSep             = { fg = plt.orange },
  texParm               = { fg = plt.pigeon },
  texRefArg             = { fg = plt.lavender },
  texRefOpt             = { link = 'texOpt' },
  texSymbol             = { fg = plt.orange },
  texTitleArg           = { link = 'Title' },
  texVerbZone           = { fg = plt.pigeon },
  texZone               = { fg = plt.aqupigeon },
  texMathArg            = { fg = plt.pigeon },
  texMathCmd            = { link = 'texCmd' },
  texMathSub            = { fg = plt.pigeon },
  texMathOper           = { fg = plt.orange },
  texMathZone           = { fg = plt.yellow },
  texMathDelim          = { fg = plt.smoke },
  texMathError          = { link = 'Error' },
  texMathGroup          = { fg = plt.pigeon },
  texMathSuper          = { fg = plt.pigeon },
  texMathSymbol         = { fg = plt.yellow },
  texMathZoneLD         = { fg = plt.pigeon },
  texMathZoneLI         = { fg = plt.pigeon },
  texMathZoneTD         = { fg = plt.pigeon },
  texMathZoneTI         = { fg = plt.pigeon },
  texMathCmdText        = { link = 'texCmd' },
  texMathZoneEnv        = { fg = plt.pigeon },
  texMathArrayArg       = { fg = plt.yellow },
  texMathCmdStyle       = { link = 'texCmd' },
  texMathDelimMod       = { fg = plt.smoke },
  texMathSuperSub       = { fg = plt.smoke },
  texMathDelimZone      = { fg = plt.pigeon },
  texMathStyleBold      = { fg = plt.smoke, bold = true },
  texMathStyleItal      = { fg = plt.smoke, italic = true },
  texMathEnvArgName     = { fg = plt.lavender },
  texMathErrorDelim     = { link = 'Error' },
  texMathDelimZoneLD    = { fg = plt.steel },
  texMathDelimZoneLI    = { fg = plt.steel },
  texMathDelimZoneTD    = { fg = plt.steel },
  texMathDelimZoneTI    = { fg = plt.steel },
  texMathZoneEnsured    = { fg = plt.pigeon },
  texMathCmdStyleBold   = { fg = plt.yellow, bold = true },
  texMathCmdStyleItal   = { fg = plt.yellow, italic = true },
  texMathStyleConcArg   = { fg = plt.pigeon },
  texMathZoneEnvStarred = { fg = plt.pigeon },

  -- lazy.nvim
  LazyDir           = { link = 'Directory' },
  LazyUrl           = { link = 'htmlLink' },
  LazySpecial       = { fg = plt.orange },
  LazyCommit        = { fg = plt.tea },
  LazyReasonFt      = { fg = plt.pigeon },
  LazyReasonCmd     = { fg = plt.yellow },
  LazyReasonPlugin  = { fg = plt.turquoise },
  LazyReasonSource  = { fg = plt.orange },
  LazyReasonRuntime = { fg = plt.lavender },
  LazyReasonEvent   = { fg = plt.flashlight },
  LazyReasonKeys    = { fg = plt.pink },
  LazyButton        = { bg = plt.ocean },
  LazyButtonActive  = { bg = plt.thunder, bold = true },
  LazyH1            = { fg = plt.space, bg = plt.yellow, bold = true },

  -- copilot.lua
  CopilotSuggestion = { fg = plt.steel, italic = true },
  CopilotAnnotation = { fg = plt.steel, italic = true },

  -- Extra highlight groups
  Yellow     = { fg = plt.yellow },
  Earth      = { fg = plt.earth },
  Orange     = { fg = plt.orange },
  Scarlet    = { fg = plt.scarlet },
  Ochre      = { fg = plt.ochre },
  Wine       = { fg = plt.wine },
  Pink       = { fg = plt.pink },
  Tea        = { fg = plt.tea },
  Flashlight = { fg = plt.flashlight },
  Aqua       = { fg = plt.aqua },
  Cerulean   = { fg = plt.cerulean },
  SkyBlue    = { fg = plt.skyblue },
  Turquoise  = { fg = plt.turquoise },
  Lavender   = { fg = plt.lavender },
  Magenta    = { fg = plt.magenta },
  Purple     = { fg = plt.purple },
  Thunder    = { fg = plt.thunder },
  White      = { fg = plt.white },
  Beige      = { fg = plt.beige },
  Pigeon     = { fg = plt.pigeon },
  Steel      = { fg = plt.steel },
  Smoke      = { fg = plt.smoke },
  Iron       = { fg = plt.iron },
  Deepsea    = { fg = plt.deepsea },
  Ocean      = { fg = plt.ocean },
  Space      = { fg = plt.space },
  Black      = { fg = plt.black },
  None       = { fg = 'NONE', bg = 'NONE' },
  Ghost      = { fg = plt.steel, italic = true },
}
-- stylua: ignore end
