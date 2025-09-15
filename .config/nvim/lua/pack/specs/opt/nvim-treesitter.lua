return {
  src = 'https://github.com/nvim-treesitter/nvim-treesitter',
  version = 'main', -- master branch is deprecated
  data = {
    build = function()
      local ts_install_ok, ts_install =
        pcall(require, 'nvim-treesitter.install')
      if ts_install_ok then
        ts_install.update()
      end
    end,
    cmds = {
      'TSInstall',
      'TSInstallFromGrammar',
      'TSUninstall',
      'TSUpdate',
    },
    -- Skip loading nvim-treesitter for plugin-specific filetypes containing
    -- underscores (e.g. 'cmp_menu') to improve initial cmdline responsiveness
    -- on slower systems
    events = { event = 'FileType', pattern = '[^_]\\+' },
  },
}
