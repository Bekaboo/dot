-- Java language server
-- https://github.com/eclipse-jdtls/eclipse.jdt.ls

local cache_home = vim.env.XDG_CACHE_HOME or vim.fs.normalize('~/.cache')
local jdtls_cache_dir = vim.fs.joinpath(cache_home, 'jdtls')
local jdtls_config_dir = vim.fs.joinpath(jdtls_cache_dir, 'config')
local jdtls_workspace_dir = vim.fs.joinpath(jdtls_cache_dir, 'workspace')

-- Config adapted from
-- https://github.com/neovim/nvim-lspconfig/blob/cb4765526f7201ce4ff0c49888f80c18da614e68/lua/lspconfig/configs/jdtls.lua#L25
return {
  cmd = {
    'jdtls',
    string.format('-configuration=%s', jdtls_config_dir),
    string.format('-data=%s', jdtls_workspace_dir),
    -- JVM args
    (function()
      if not vim.env.JDTLS_JVM_ARGS then
        return
      end
      return unpack(vim
        .iter(require('utils.cmd').split(vim.env.JDTLS_JVM_ARGS))
        :map(function(arg)
          return string.format('--jvm-arg=%s', arg)
        end)
        :totable())
    end)(),
  },
  filetypes = { 'java' },
  root_markers = {
    { 'build.gradle', 'build.gradle.kts' },
    {
      'build.xml',
      'pom.xml',
      'settings.gradle',
      'settings.gradle.kts',
    },
  },
  init_options = {
    workspace = jdtls_workspace_dir,
    jvm_args = {},
    -- Java debugger settings, see:
    -- https://codeberg.org/mfussenegger/nvim-dap/wiki/Java#via-other-language-server-clients
    -- https://github.com/microsoft/java-debug?tab=readme-ov-file#usage-with-eclipsejdtls
    bundles = { '/usr/share/java-debug/com.microsoft.java.debug.plugin.jar' },
  },
}
