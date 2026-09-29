-- Format terraform config file with `terraform fmt` and lint with
-- `terraform validate`
-- https://developer.hashicorp.com/terraform/cli

return {
  filetypes = { 'terraform', 'terraform-vars', 'hcl' },
  cmd = { 'efm-langserver' },
  requires = { 'terraform' },
  name = 'terraform',
  init_options = {
    documentFormatting = true,
  },
  settings = {
    languages = {
      terraform = {
        {
          formatCommand = 'terraform fmt -',
          formatStdin = true,
        },
        {
          lintSource = 'terraform',
          lintCommand = [[terraform validate -json | jq -r '.diagnostics[] | "\(.severity) \(.range.filename):\(.range.start.line):\(.range.start.column): \(.summary). \(.detail)"']],
          lintFormats = {
            '%trror %f:%l:%c: %m',
            '%tarning %f:%l:%c: %m',
          },
          lintAfterOpen = true,
          lintStdin = false,
          lintWorkSpace = true,
          lintIgnoreExitCode = true,
        },
      },
    },
  },
}
