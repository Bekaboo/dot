-- stylua: ignore start
return {
  debug = {
    Breakpoint          = 'B ',
    BreakpointCondition = 'C ',
    BreakpointLog       = 'L ',
    BreakpointRejected  = 'X ',
    Disconnect          = 'x ',
    Pause               = '= ',
    Restart             = '@ ',
    StackFrame          = '> ',
    StackFrameCurrent   = '>*',
    Start               = '+ ',
    StepBack            = '< ',
    StepInto            = 'v ',
    StepOut             = '^ ',
    StepOver            = '> ',
    Stop                = '- ',
  },
  diagnostics = {
    DiagnosticSignError = 'E ',
    DiagnosticSignHint  = 'H ',
    DiagnosticSignInfo  = 'I ',
    DiagnosticSignOk    = 'O ',
    DiagnosticSignWarn  = 'W ',
  },
  kinds = {
    Array               = 'Arr ',
    Boolean             = 'Bool ',
    BreakStatement      = 'Brk ',
    Calculator          = 'Calc ',
    Call                = 'Call ',
    CaseStatement       = 'Case ',
    Class               = 'Class ',
    Cmd                 = 'Cmd ',
    Color               = 'Col ',
    Constant            = 'Const ',
    Constructor         = 'Constructor ',
    ContinueStatement   = 'Cont ',
    Copilot             = 'Copilot ',
    Declaration         = 'Decl ',
    Delete              = 'Del ',
    DoStatement         = 'Do ',
    Element             = 'Elem ',
    Enum                = 'Enum ',
    EnumMember          = 'EnumM ',
    Event               = 'Event ',
    Field               = 'Field ',
    File                = 'File ',
    Folder              = 'Dir ',
    ForStatement        = 'For ',
    Format              = 'Fmt ',
    Function            = 'Fn ',
    GitBranch           = 'Git ',
    H1Marker            = 'H1 ',
    H2Marker            = 'H2 ',
    H3Marker            = 'H3 ',
    H4Marker            = 'H4 ',
    H5Marker            = 'H5 ',
    H6Marker            = 'H6 ',
    Identifier          = 'Id ',
    IfStatement         = 'If ',
    Interface           = 'Interface ',
    Keyboard            = 'Key ',
    Keyword             = 'Keyword ',
    Lazy                = 'Lazy ',
    List                = 'List ',
    Log                 = 'Log ',
    Lsp                 = 'Lsp ',
    Macro               = 'Macro ',
    MarkdownH1          = 'H1 ',
    MarkdownH2          = 'H2 ',
    MarkdownH3          = 'H3 ',
    MarkdownH4          = 'H4 ',
    MarkdownH5          = 'H5 ',
    MarkdownH6          = 'H6 ',
    Method              = 'Method ',
    Module              = 'Mod ',
    Namespace           = 'Ns ',
    Neovim              = 'Nvim ',
    Null                = 'Nnull ',
    Number              = 'Num ',
    Object              = 'Obj ',
    Operator            = 'Op ',
    Package             = 'Pkg ',
    Pair                = 'Pair ',
    Property            = 'Prop ',
    Reference           = 'Ref ',
    Regex               = 'Regex ',
    Repeat              = 'Rep ',
    RuleSet             = 'Rule ',
    Scope               = 'Scope ',
    Snippet             = 'Snip ',
    Specifier           = 'Spec ',
    Statement           = 'Statement ',
    String              = 'Str ',
    Struct              = 'Struct ',
    SwitchStatement     = 'Switch ',
    Terminal            = 'Term ',
    Text                = 'Text ',
    Type                = 'Type ',
    TypeParameter       = 'TypeParam ',
    Unit                = 'Unit ',
    Value               = 'Val ',
    Variable            = 'Var ',
    WhileStatement      = 'While ',
  },
  ft = {
    Assembly            = 'A ',
    Bak                 = 'B ',
    Config              = 'C ',
    Cuda                = 'C ',
    Data                = 'D ',
    Desktop             = 'D ',
    Elisp               = 'E ',
    Git                 = 'G ',
    Ipynb               = 'I ',
    Java                = 'J ',
    Lock                = 'L ',
    Lua                 = 'L ',
    Markdown            = 'M ',
    Object              = 'O ',
    Pdf                 = 'P ',
    Raw                 = 'R ',
    Sh                  = 'S ',
    Txt                 = 'T ',
    Theme               = 'T ',
    Video               = 'V ',
    Vim                 = 'V ',
    Zip                 = 'Z ',
  },
  ui = {
    AngleDown           = 'v ',
    AngleLeft           = '< ',
    AngleRight          = '> ',
    AngleUp             = '^ ',
    ArrowDown           = '↓ ',
    ArrowLeft           = '← ',
    ArrowLeftRight      = '↔ ',
    ArrowRight          = '→ ',
    ArrowUp             = '↑ ',
    ArrowUpDown         = '↕ ',
    Bullet1             = '- ',
    Bullet2             = '- ',
    CircleFilled        = '• ',
    CircleOutline       = 'o ',
    Cross               = 'x ',
    Diamond             = '◆ ',
    Dot                 = '• ',
    DotLarge            = '• ',
    Ellipsis            = '. ',
    GitSignAdd          = '+ ',
    GitSignChange       = '~ ',
    GitSignChangedelete = '= ',
    GitSignDelete       = '- ',
    GitSignTopdelete    = '- ',
    GitSignUntracked    = '+ ',
    Log                 = '= ',
    Ok                  = 'v ',
    Pin                 = '* ',
    Play                = '> ',
    Star                = '* ',
    TriangleDown        = '▼ ',
    TriangleLeft        = '◀ ',
    TriangleRight       = '▶ ',
    TriangleUp          = '▲ ',
  },
  keys = {
    BackSpace           = '← ',
    Command             = 'Cmd ',
    Control             = 'Ctrl ',
    Down                = '↓ ',
    Enter               = 'CR ',
    Escape              = 'Esc ',
    F1                  = 'F1 ',
    F10                 = 'F10 ',
    F11                 = 'F11 ',
    F12                 = 'F12 ',
    F2                  = 'F2 ',
    F3                  = 'F3 ',
    F4                  = 'F4 ',
    F5                  = 'F5 ',
    F6                  = 'F6 ',
    F7                  = 'F7 ',
    F8                  = 'F8 ',
    F9                  = 'F9 ',
    Left                = '← ',
    Meta                = 'Meta ',
    MouseDown           = 'Mouse↓ ',
    MouseUp             = 'Mouse↑ ',
    Right               = '→ ',
    Shift               = 'Shift ',
    Space               = 'Spc ',
    Tab                 = 'Tab ',
    Up                  = '↑ ',
  }
}
-- stylua: ignore end
