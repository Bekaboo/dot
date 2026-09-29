-- ShellCheck is an open source static analysis tool that automatically finds bugs in your shell scripts
-- https://github.com/koalaman/shellcheck

local lang_settings = {
  {
    lintCommand = 'shellcheck -f gcc -',
    lintFormats = {
      '-:%l:%c: %trror: %m [SC%n]',
      '-:%l:%c: %tarning: %m [SC%n]',
      '-:%l:%c: %tnfo: %m [SC%n]',
      '-:%l:%c: %tote: %m [SC%n]',
    },
    lintAfterOpen = true,
    lintStdin = true,
  },
}

---@type my.lsp.config
return {
  filetypes = { 'bash', 'sh' },
  cmd = { 'efm-langserver' },
  requires = { 'shellcheck' },
  name = 'shellcheck',
  settings = {
    languages = {
      sh = lang_settings,
      bash = lang_settings,
    },
  },
}
