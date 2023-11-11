<h1 align="center"> Bekaboo's Neovim Configuration </h1>

<center>
    <div>
        <img src="https://github.com/Bekaboo/nvim/assets/76579810/ff20fc73-4d21-478b-ae13-728832e4f3db" width=47.5%>
        <img src="https://github.com/Bekaboo/nvim/assets/76579810/1f2ceeaf-3b78-4777-afc7-db0b7f6ba69a" width=47.5%>
    </div>
</center>

## Table of Contents

<!--toc:start-->
- [Table of Contents](#table-of-contents)
- [Features](#features)
- [Requirements and Dependencies](#requirements-and-dependencies)
  - [Basic](#basic)
  - [Tree-sitter](#tree-sitter)
  - [LSP](#lsp)
  - [DAP](#dap)
  - [Formatter](#formatter)
  - [Other External Tools](#other-external-tools)
- [Installation](#installation)
- [Config Structure](#config-structure)
- [Tweaking this Configuration](#tweaking-this-configuration)
  - [Managing Plugins with Modules](#managing-plugins-with-modules)
  - [Installing Packages to an Existing Module](#installing-packages-to-an-existing-module)
  - [Installing Packages to a New Module](#installing-packages-to-a-new-module)
  - [General Settings and Options](#general-settings-and-options)
  - [Keymaps](#keymaps)
  - [Colorscheme](#colorscheme)
  - [Auto Commands](#auto-commands)
  - [LSP Server Configurations](#lsp-server-configurations)
  - [DAP Configurations](#dap-configurations)
  - [Snippets](#snippets)
  - [Enabling VSCode Integration](#enabling-vscode-integration)
- [Appendix](#appendix)
  - [Default Modules and Plugins of Choice](#default-modules-and-plugins-of-choice)
    - [Third Party Plugins](#third-party-plugins)
    - [Local Plugins](#local-plugins)
  - [Startuptime Profiling](#startuptime-profiling)
<!--toc:end-->

## Features

- Modular design
    - Install and manage packages in groups
    - Make it easy to use different set of configuration for different use
      cases
- [VSCode-Neovim](https://github.com/vscode-neovim/vscode-neovim) integration
    - Feels at home in VSCode when you occasionally need it
- Massive [TeX math snippets](https://github.com/Bekaboo/nvim/blob/master/lua/snippets/shared/math.lua)
- Custom UI elements ([statusline](https://github.com/Bekaboo/nvim/blob/master/plugin/statusline.lua), [statuscolumn](https://github.com/Bekaboo/nvim/blob/master/plugin/statuscolumn.lua), [winbar](https://github.com/Bekaboo/nvim/tree/master/lua/plugin/winbar)) and [colorschemes](https://github.com/Bekaboo/nvim/tree/master/colors)
- [Fine-tuned plugins](https://github.com/Bekaboo/nvim/tree/master/lua/configs) with [custom patches](https://github.com/Bekaboo/nvim/tree/master/patches)
- Fast startup around [15 ~ 35 ms](#startuptime-profiling)

## Requirements and Dependencies

### Basic

- [Neovim](https://github.com/neovim/neovim) ***nightly***
- [Git](https://git-scm.com/)
- A decent terminal emulator
- A nerd font, e.g. [JetbrainsMono Nerd Font](https://github.com/ryanoasis/nerd-fonts/tree/master/patched-fonts/JetBrainsMono)

### Tree-sitter

Tree-sitter installation and configuration is handled by [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter).

To add or remove support for a language, install or uninstall the corresponding
parser using `:TSInstall` or `:TSUninstall`.

To make the change persistent, add or remove corresponding entries in `M.langs`
in [lua/utils/static.lua](https://github.com/Bekaboo/nvim/blob/master/lua/utils/static.lua).

### LSP

For LSP support, install the following language servers manually use your
favorite package manager:

- Bash: install [BashLS](https://github.com/bash-lsp/bash-language-server)

    Example for ArchLinux users:

    ```sh
    sudo pacman -S bash-language-server
    ```

- C/C++: install [Clang](https://clang.llvm.org/)
- Lua: install [LuaLS](https://github.com/LuaLS/lua-language-server)
- Python: install [PyLSP](https://github.com/python-lsp/python-lsp-server)
- Rust: install [Rust Analyzer](https://rust-analyzer.github.io/)
- LaTeX: install [TexLab](https://github.com/latex-lsp/texlab)
- VimL: install [VimLS](https://github.com/iamcco/vim-language-server)
- Markdown: install [Marksman](https://github.com/artempyanykh/marksman)
- \*General-purpose LSP: install [EFM Language Server](https://github.com/mattn/efm-langserver)
    - Already configured for [Black](https://github.com/psf/black), [Shfmt](https://github.com/mvdan/sh), and [StyLua](https://github.com/JohnnyMorganz/StyLua)
    - Find configuration in [lua/configs/lsp-server-configs/efm.lua](https://github.com/Bekaboo/nvim/tree/master/lua/configs/lsp-server-configs/efm.lua)

To add support for other languages, install corresponding LS manually and
append the language and its language server to `M.langs` in [lua/utils/static.lua](https://github.com/Bekaboo/nvim/blob/master/lua/utils/static.lua)
so that [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) will pick them up.

### DAP

Install the following debug adapters manually:

- Bash:

    Go to [vscode-bash-debug release page](https://github.com/rogalmic/vscode-bash-debug/releases),
    download the latest release (`bash-debug-x.x.x.vsix`), extract
    (change the extension from `.vsix` to `.zip` then unzip it) the contents
    to a new directory `vscode-bash-debug/` and put it under stdpath `data`
    (see `:h stdpath`).

    Make sure `node` is executable.

- C/C++: install [CodeLLDB](https://github.com/vadimcn/codelldb).

    Example for ArchLinux users:

    ```sh
    yay -S codelldb     # Install from AUR
    ```

- Python: install [DebugPy](https://github.com/microsoft/debugpy)

    Example for ArchLinux users:

    ```sh
    sudo pacman -S python-debugpy
    ```

    or

    ```sh
    pip install --local debugpy # Install to user's home directory
    ```

### Formatter

- Bash: install [Shfmt](https://github.com/mvdan/sh)
- C/C++: install [Clang](https://clang.llvm.org/) to use `clang-format`
- Lua: install [StyLua](https://github.com/JohnnyMorganz/StyLua)
- Rust: install [Rust](https://www.rust-lang.org/tools/install) to use `rustfmt`
- Python: install [Black](https://github.com/psf/black)
- LaTeX: install [texlive-core](http://tug.org/texlive/) to use `latexindent`

### Other External Tools

- [Lazygit](https://github.com/jesseduffield/lazygit) for improved git integration
- [Fd](https://github.com/sharkdp/fd), [Ripgrep](https://github.com/BurntSushi/ripgrep), and [Fzf](https://github.com/junegunn/fzf) for fuzzy search
- [Pandoc](https://pandoc.org/), [custom scripts](https://github.com/Bekaboo/dot/tree/master/.scripts) and [TexLive](https://www.tug.org/texlive/) (for ArchLinux users, it is `texlive-core` and `texlive-extra`) for markdown → PDF conversion

## Installation

1. Backup your own settings.
2. Make sure you have satisfied the requirements.
3. Clone this repo to your config directory
    ```
    git clone https://github.com/Bekaboo/nvim ~/.config/nvim
    ```
4. Open neovim, manually run `:Lazy sync` if lazy.nvim does not
    automatically sync.
5. Run `:checkhealth` to check potential dependency issues.
6. Enjoy!

## Config Structure

```
.
├── colors                      # colorschemes
├── plugin                      # custom plugins
├── ftplugin                    # custom filetype plugins
├── init.lua                    # entry of config
├── lua
│   ├── init                    # files under this folder is required by 'init.lua'
│   │   ├── autocmds.lua
│   │   ├── general.lua         # options and general settings
│   │   ├── keymaps.lua
│   │   └── plugins.lua         # specify which modules to use in different conditions
│   ├── modules                 # all plugin specifications and configs go here
│   │   ├── lib.lua             # plugin specifications in module 'lib'
│   │   ├── completion.lua      # plugin specifications in module 'completion'
│   │   ├── debug.lua           # plugin specifications in modules 'debug'
│   │   ├── lsp.lua             # plugin specifications in module 'lsp'
│   │   ├── markup.lua          # ...
│   │   ├── misc.lua
│   │   ├── tools.lua
│   │   ├── treesitter.lua
│   │   └── ui.lua
│   ├── configs                 # configs for each plugin
│   ├── snippets                # snippets
│   ├── plugin                  # the actual implementation of custom plugins
│   └── utils
└── syntax                      # syntax files
```

## Tweaking this Configuration

### Managing Plugins with Modules

In order to enable or disable a module, one need to change the table in
[lua/init/plugins.lua](https://github.com/Bekaboo/nvim/blob/master/lua/init/plugins.lua) passed to `manage_plugins()`, for example

```lua
enable_modules({
  'lib',
  'treesitter',
  'edit',
  -- ...
})
```

the format of argument passed to `manage_plugins` is the same as that passed to
lazy.nvim's setup function.

### Installing Packages to an Existing Module

To install plugin `foo` under module `bar`, just insert the
corresponding specification to the big table
`lua/modules/bar.lua` returns, for instance,

`lua/modules/bar.lua`:

```lua
return {
  -- ...
  {
    'foo/foo',
    dependencies = 'foo_dep',
  },
}
```

### Installing Packages to a New Module

To install plugin `foo` under module `bar`, one should first
create module `bar` under [lua/modules](https://github.com/Bekaboo/nvim/tree/master/lua/modules):

```
.
└── lua
    └── modules
        └── bar.lua
```

a module should return a big table containing all specifications of plugins
under that module, for instance:

```lua
return {
  {
    'goolord/alpha-nvim',
    cond = function()
      return vim.fn.argc() == 0 and
          vim.o.lines >= 36 and vim.o.columns >= 80
    end,
    dependencies = 'nvim-web-devicons',
  },

  {
    'romgrk/barbar.nvim',
    dependencies = 'nvim-web-devicons',
    config = function() require('bufferline').setup() end,
  },
}
```

After creating the new module `bar`, enable it in [lua/init/plugins.lua](hub.com/Bekaboo/nvim/blob/master/lua/init/plugins.lua):

```lua
enable_modules({
  -- ...
  'bar',
  -- ...
})
```

### General Settings and Options

See [lua/init/general.lua](https://github.com/Bekaboo/nvim/blob/master/lua/init/general.lua).

### Keymaps

See [lua/init/keymaps.lua](https://github.com/Bekaboo/nvim/blob/master/lua/init/keymaps.lua), or see module config files for
corresponding plugin keymaps.

### Colorscheme

- Nano

    <div>
        <img src="https://github.com/Bekaboo/nvim/assets/76579810/a79e1322-114c-46c8-80ff-c29129f8cb2a" width=47.5%>
        <img src="https://github.com/Bekaboo/nvim/assets/76579810/be61e9bf-84d8-472a-a3b1-a0d2962e636a" width=47.5%>
    </div>

- Cockatoo

    <div>
        <img src="https://github.com/Bekaboo/nvim/assets/76579810/de4c61f6-a8a8-409d-bb6d-6bb144e65832" width=47.5%>
        <img src="https://github.com/Bekaboo/nvim/assets/76579810/035eb032-bbe5-48a5-abaf-4b334516c2cd" width=47.5%>
    </div>

`cockatoo` and `nano` are two builtin custom colorschemes, with seperate
palettes for dark and light background.

Neovim is configured to restore the previous background and colorscheme
settings on startup, so there is no need to set them up in the config
file explicitly.

To disable the auto-restore feature, remove corresponding lines in
[lua/init/autocmds.lua](https://github.com/Bekaboo/nvim/blob/master/lua/init/autocmds.lua)

To tweak this colorscheme, see [colors/cockatoo.lua](https://github.com/Bekaboo/nvim/tree/master/colors/cockatoo.lua) and [colors/nano.lua](https://github.com/Bekaboo/nvim/tree/master/colors/nano.lua)

### Auto Commands

See [lua/init/autocmds.lua](https://github.com/Bekaboo/nvim/blob/master/lua/init/autocmds.lua).

### LSP Server Configurations

See [lua/configs/lsp-server-configs](https://github.com/Bekaboo/nvim/tree/master/lua/configs/lsp-server-configs) and [lua/configs/nvim-lspconfig.lua](https://github.com/Bekaboo/nvim/tree/master/lua/configs/nvim-lspconfig.lua).

### DAP Configurations

See [lua/configs/dap-configs](https://github.com/Bekaboo/nvim/tree/master/lua/configs/dap-configs), [lua/configs/nvim-dap.lua](https://github.com/Bekaboo/nvim/tree/master/lua/configs/nvim-dap.lua), and [lua/configs/nvim-dap-ui.lua](https://github.com/Bekaboo/nvim/tree/master/lua/configs/nvim-dap-ui.lua).

### Snippets

This configuration use [LuaSnip](https://github.com/L3MON4D3/LuaSnip) as the snippet engine,
custom snippets for different filetypes
are defined under [lua/snippets](https://github.com/Bekaboo/nvim/tree/master/lua/snippets).

### Enabling VSCode Integration

VSCode integration takes advantages of the modular design, allowing to use
a different set of modules when Neovim is launched by VSCode, relevant code is
in [plugin/vscode-neovim.vim](https://github.com/Bekaboo/nvim/blob/master/plugin/vscode-neovim.vim) and [lua/init/plugins.lua](https://github.com/Bekaboo/nvim/blob/master/lua/init/plugins.lua).

To make VSCode integration work, please install [VSCode-Neovim](https://github.com/vscode-neovim/vscode-neovim) in VSCode
and configure it correctly.

After setting up VSCode-Neovim, re-enter VSCode, open a random file
and it should work out of the box.

## Appendix

### Default Modules and Plugins of Choice

#### Third Party Plugins

Total # of plugins: 43 (package manager included).

- **Lib**
    - [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
    - [nvim-web-devicons](https://github.com/kyazdani42/nvim-web-devicons)
    - [telescope-fzf-native.nvim](https://github.com/nvim-telescope/telescope-fzf-native.nvim)
- **Completion**
    - [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)
    - [cmp-calc](https://github.com/hrsh7th/cmp-calc)
    - [cmp-cmdline](https://github.com/hrsh7th/cmp-cmdline)
    - [cmp-nvim-lsp](https://github.com/hrsh7th/cmp-nvim-lsp)
    - [fuzzy.nvim](https://github.com/tzachar/fuzzy.nvim)
    - [cmp-fuzzy-path](https://github.com/tzachar/cmp-fuzzy-path)
    - [cmp-buffer](https://github.com/hrsh7th/cmp-buffer)
    - [cmp_luasnip](https://github.com/saadparwaiz1/cmp_luasnip)
    - [cmp-nvim-lsp-signature-help](https://github.com/hrsh7th/cmp-nvim-lsp-signature-help)
    - [cmp-dap](https://github.com/rcarriga/cmp-dap)
    - [copilot.lua](https://github.com/zbirenbaum/copilot.lua)
    - [LuaSnip](https://github.com/L3MON4D3/LuaSnip)
- **LSP**
    - [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig)
    - [clangd_extensions.nvim](https://github.com/p00f/clangd_extensions.nvim)
    - [glance.nvim](https://github.com/dnlhc/glance.nvim)
- **Markup**
    - [vimtex](https://github.com/lervag/vimtex)
    - [markdown-preview.nvim](https://github.com/iamcco/markdown-preview.nvim)
    - [vim-table-mode](https://github.com/dhruvasagar/vim-table-mode)
- **Edit**
    - [nvim-surround](https://github.com/kylechui/nvim-surround)
    - [Comment.nvim](https://github.com/numToStr/Comment.nvim)
    - [vim-sleuth](https://github.com/tpope/vim-sleuth)
    - [nvim-autopairs](https://github.com/windwp/nvim-autopairs)
    - [fcitx.nvim](https://github.com/h-hg/fcitx.nvim)
    - [vim-easy-align](https://github.com/junegunn/vim-easy-align)
- **Tools**
    - [fzf-lua](https://github.com/ibhagwan/fzf-lua)
    - [flatten.nvim](https://github.com/willothy/flatten.nvim)
    - [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim)
    - [git-conflict](akinsho/git-conflict.nvim)
    - [nvim-colorizer.lua](https://github.com/NvChad/nvim-colorizer.lua)
    - [vim-fugitive](https://github.com/tpope/vim-fugitive)
- **Treesitter**
    - [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
    - [nvim-treesitter-textobjects](https://github.com/nvim-treesitter/nvim-treesitter-textobjects)
    - [nvim-ts-context-commentstring](https://github.com/JoosepAlviste/nvim-ts-context-commentstring)
    - [nvim-treesitter-endwise](https://github.com/RRethy/nvim-treesitter-endwise)
    - [treesj](https://github.com/Wansmer/treesj)
    - [cellular-automaton.nvim](https://github.com/Eandrju/cellular-automaton.nvim)
- **DEBUG**
    - [nvim-dap](https://github.com/mfussenegger/nvim-dap)
    - [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui)
    - [one-small-step-for-vimkind](https://github.com/jbyuki/one-small-step-for-vimkind)

#### Local Plugins

- [colorcolumn](https://github.com/Bekaboo/nvim/tree/master/plugin/colorcolumn.lua)
    - shows color column dynamically based on current line width
    - released as [deadcolumn.nvim](https://github.com/Bekaboo/deadcolumn.nvim)
- [expandtab](https://github.com/Bekaboo/nvim/tree/master/plugin/expandtab.lua)
    - always use spaces for alignment
- [readline](https://github.com/Bekaboo/nvim/tree/master/plugin/readline.lua)
    - readline-like keybindings in insert and command mode
- [statuscolumn](https://github.com/Bekaboo/nvim/tree/master/plugin/statuscolumn.lua)
    - custom statuscolumn, with git signs on the right of line numbers
- [statusline](https://github.com/Bekaboo/nvim/tree/master/plugin/statusline.lua)
    - custom statusline inspired by [nano-emacs](https://github.com/rougier/nano-emacs)
- [tabout](https://github.com/Bekaboo/nvim/tree/master/plugin/tabout.lua)
    - tab in and out with `<Tab>` and `<S-Tab>`
- [vscode-neovim](https://github.com/Bekaboo/nvim/tree/master/plugin/vscode-neovim.vim)
    - integration with [VSCode-Neovim](https://github.com/vscode-neovim/vscode-neovim)
- [winbar](https://github.com/Bekaboo/nvim/blob/master/plugin/winbar.lua)
    - a winbar with drop-down menus and multiple backends
    - released as [dropbar.nvim](https://github.com/Bekaboo/dropbar.nvim)

### Startuptime Profiling

- Last update: 2023-11-07

- Neovim Version:

    ```
    NVIM v0.10.0-dev-1452+g363e029e7ae
    Build type: RelWithDebInfo
    LuaJIT 2.1.1697887905
    Run "nvim -V1 -v" for more info
    ```

- Config Commit: `02172098091cf5b1b93bb9b5af2d4e21c128499e` (#2021)

- System: Arch Linux 6.1.61-1-lts

- Machine: Dell XPS-13-7390

- Command: `nvim --startuptime startuptime.log +'call timer_start(0, {-> execute('\''qall!'\'')})'`

    <details>
      <summary>startuptime log</summary>

      ```
        times in msec
         clock   self+sourced   self:  sourced script
         clock   elapsed:              other lines

        000.006  000.006: --- NVIM STARTING ---
        000.121  000.115: event init
        000.179  000.058: early init
        000.218  000.039: locale set
        000.255  000.037: init first window
        000.478  000.223: inits 1
        000.492  000.014: window checked
        000.495  000.003: parsing arguments
        000.920  000.073  000.073: require('vim.shared')
        001.012  000.038  000.038: require('vim.inspect')
        001.058  000.032  000.032: require('vim._options')
        001.059  000.136  000.066: require('vim._editor')
        001.060  000.255  000.046: require('vim._init_packages')
        001.063  000.313: init lua interpreter
        001.108  000.046: expanding arguments
        001.122  000.014: inits 2
        001.392  000.270: init highlight
        001.393  000.001: waiting for UI
        001.493  000.100: done waiting for UI
        001.504  000.011: clear screen
        001.520  000.007  000.007: require('vim.keymap')
        001.743  000.232: init default mappings & autocommands
        002.245  000.050  000.050: sourcing /usr/share/nvim/runtime/ftplugin.vim
        002.308  000.027  000.027: sourcing /usr/share/nvim/runtime/indent.vim
        002.360  000.011  000.011: sourcing /usr/share/nvim/archlinux.vim
        002.363  000.029  000.018: sourcing /etc/xdg/nvim/sysinit.vim
        003.267  000.869  000.869: require('init.general')
        003.578  000.027  000.027: require('utils')
        005.382  000.116  000.116: require('utils.keymap')
        005.529  002.259  002.115: require('init.keymaps')
        005.896  000.364  000.364: require('init.autocmds')
        006.685  000.535  000.535: require('modules.lib')
        006.788  000.095  000.095: require('modules.completion')
        006.835  000.041  000.041: require('modules.debug')
        006.882  000.042  000.042: require('modules.edit')
        006.918  000.032  000.032: require('modules.lsp')
        006.955  000.033  000.033: require('modules.markup')
        007.053  000.057  000.057: require('modules.tools')
        007.121  000.046  000.046: require('modules.treesitter')
        007.148  000.023  000.023: require('modules.colorschemes')
        007.274  000.122  000.122: require('lazy')
        007.307  000.019  000.019: require('ffi')
        007.460  000.114  000.114: require('vim.uri')
        007.476  000.166  000.052: require('vim.loader')
        007.542  000.030  000.030: require('vim.fs')
        007.818  000.323  000.293: require('lazy.stats')
        007.972  000.126  000.126: require('lazy.core.util')
        008.178  000.203  000.203: require('lazy.core.config')
        008.419  000.058  000.058: require('lazy.core.handler')
        008.502  000.080  000.080: require('lazy.core.plugin')
        008.509  000.329  000.191: require('lazy.core.loader')
        009.920  000.116  000.116: require('lazy.core.handler.event')
        009.924  000.223  000.108: require('lazy.core.handler.ft')
        010.006  000.078  000.078: require('lazy.core.handler.keys')
        010.117  000.107  000.107: require('lazy.core.handler.cmd')
        010.558  000.028  000.028: sourcing /home/zeng/.local/share/nvim/site/pack/packages/opt/vimtex/ftdetect/cls.vim
        010.601  000.019  000.019: sourcing /home/zeng/.local/share/nvim/site/pack/packages/opt/vimtex/ftdetect/tex.vim
        010.639  000.016  000.016: sourcing /home/zeng/.local/share/nvim/site/pack/packages/opt/vimtex/ftdetect/tikz.vim
        012.476  000.197  000.197: sourcing /usr/share/nvim/runtime/filetype.lua
        013.353  000.177  000.177: require('utils.hl')
        013.396  000.279  000.102: sourcing /home/zeng/.config/nvim/plugin/colorcolumn.lua
        013.501  000.076  000.076: sourcing /home/zeng/.config/nvim/plugin/colorswitch.lua
        013.583  000.056  000.056: sourcing /home/zeng/.config/nvim/plugin/expandtab.lua
        013.733  000.126  000.126: sourcing /home/zeng/.config/nvim/plugin/fzf-file-explorer.lua
        014.013  000.252  000.252: sourcing /home/zeng/.config/nvim/plugin/lazygit.lua
        014.169  000.128  000.128: sourcing /home/zeng/.config/nvim/plugin/lsp-diagnostic.lua
        014.288  000.091  000.091: sourcing /home/zeng/.config/nvim/plugin/readline.lua
        014.527  000.076  000.076: require('utils.stl')
        014.555  000.238  000.162: sourcing /home/zeng/.config/nvim/plugin/statuscolumn.lua
        014.706  000.123  000.123: sourcing /home/zeng/.config/nvim/plugin/statusline.lua
        014.790  000.055  000.055: sourcing /home/zeng/.config/nvim/plugin/tabout.lua
        014.851  000.036  000.036: sourcing /home/zeng/.config/nvim/plugin/termopts.lua
        014.955  000.059  000.059: sourcing /home/zeng/.config/nvim/plugin/textobj-fold.lua
        015.054  000.076  000.076: sourcing /home/zeng/.config/nvim/plugin/tmux.lua
        015.093  000.014  000.014: sourcing /home/zeng/.config/nvim/plugin/vscode-neovim.vim
        015.158  000.044  000.044: sourcing /home/zeng/.config/nvim/plugin/winbar.lua
        015.301  000.044  000.044: sourcing /usr/share/nvim/runtime/plugin/editorconfig.lua
        015.344  000.015  000.015: sourcing /usr/share/nvim/runtime/plugin/gzip.vim
        015.417  000.050  000.050: sourcing /usr/share/nvim/runtime/plugin/man.lua
        015.458  000.016  000.016: sourcing /usr/share/nvim/runtime/plugin/matchit.vim
        015.665  000.184  000.184: sourcing /usr/share/nvim/runtime/plugin/matchparen.vim
        015.713  000.020  000.020: sourcing /usr/share/nvim/runtime/plugin/netrwPlugin.vim
        015.783  000.047  000.047: sourcing /usr/share/nvim/runtime/plugin/nvim.lua
        015.984  000.176  000.176: sourcing /usr/share/nvim/runtime/plugin/rplugin.vim
        016.072  000.061  000.061: sourcing /usr/share/nvim/runtime/plugin/shada.vim
        016.143  000.024  000.024: sourcing /usr/share/nvim/runtime/plugin/spellfile.vim
        016.188  000.016  000.016: sourcing /usr/share/nvim/runtime/plugin/tarPlugin.vim
        016.225  000.012  000.012: sourcing /usr/share/nvim/runtime/plugin/tohtml.vim
        016.266  000.020  000.020: sourcing /usr/share/nvim/runtime/plugin/tutor.vim
        016.308  000.016  000.016: sourcing /usr/share/nvim/runtime/plugin/zipPlugin.vim
        016.577  010.678  005.468: require('init.plugins')
        016.580  014.196  000.026: sourcing /home/zeng/.config/nvim/init.lua
        016.588  000.542: sourcing vimrc file(s)
        016.828  000.082  000.082: sourcing /usr/share/nvim/runtime/filetype.lua
        017.025  000.080  000.080: sourcing /usr/share/nvim/runtime/syntax/synload.vim
        017.108  000.224  000.144: sourcing /usr/share/nvim/runtime/syntax/syntax.vim
        017.129  000.235: inits 3
        018.975  001.846: reading ShaDa
        019.164  000.009  000.009: require('vim.F')
        019.492  000.255  000.255: sourcing /usr/share/nvim/runtime/autoload/provider/clipboard.vim
        019.661  000.421: opening buffers
        019.687  000.027: BufEnter autocommands
        019.691  000.004: editing files in windows
        019.704  000.013: executing command arguments
        019.706  000.002: VimEnter autocommands
        021.749  001.265  001.265: sourcing /home/zeng/.config/nvim/colors/nano.lua
        021.935  000.964: UIEnter autocommands
        021.939  000.004: before starting main loop
        022.348  000.074  000.074: require('utils.git')
        022.500  000.143  000.143: require('vim._system')
        024.289  002.133: first screen update
        024.292  000.003: --- NVIM STARTED ---
      ```

    </details>

    <details>
      <summary>statistics of 100 startups (sorted)</summary>

      ```
        023.286  000.003: --- NVIM STARTED ---
        023.336  000.003: --- NVIM STARTED ---
        023.382  000.003: --- NVIM STARTED ---
        023.473  000.003: --- NVIM STARTED ---
        023.567  000.004: --- NVIM STARTED ---
        023.569  000.003: --- NVIM STARTED ---
        023.584  000.003: --- NVIM STARTED ---
        023.635  000.004: --- NVIM STARTED ---
        023.649  000.003: --- NVIM STARTED ---
        023.672  000.003: --- NVIM STARTED ---
        023.675  000.004: --- NVIM STARTED ---
        023.677  000.003: --- NVIM STARTED ---
        023.687  000.003: --- NVIM STARTED ---
        023.698  000.004: --- NVIM STARTED ---
        023.701  000.003: --- NVIM STARTED ---
        023.724  000.003: --- NVIM STARTED ---
        023.727  000.003: --- NVIM STARTED ---
        023.747  000.004: --- NVIM STARTED ---
        023.796  000.003: --- NVIM STARTED ---
        023.805  000.003: --- NVIM STARTED ---
        023.828  000.004: --- NVIM STARTED ---
        023.835  000.003: --- NVIM STARTED ---
        023.856  000.003: --- NVIM STARTED ---
        023.886  000.003: --- NVIM STARTED ---
        023.911  000.003: --- NVIM STARTED ---
        023.912  000.005: --- NVIM STARTED ---
        023.946  000.012: --- NVIM STARTED ---
        023.947  000.004: --- NVIM STARTED ---
        023.948  000.003: --- NVIM STARTED ---
        023.961  000.005: --- NVIM STARTED ---
        023.969  000.003: --- NVIM STARTED ---
        023.992  000.004: --- NVIM STARTED ---
        024.003  000.004: --- NVIM STARTED ---
        024.006  000.011: --- NVIM STARTED ---
        024.047  000.004: --- NVIM STARTED ---
        024.050  000.003: --- NVIM STARTED ---
        024.087  000.003: --- NVIM STARTED ---
        024.089  000.005: --- NVIM STARTED ---
        024.093  000.003: --- NVIM STARTED ---
        024.141  000.003: --- NVIM STARTED ---
        024.145  000.003: --- NVIM STARTED ---
        024.182  000.003: --- NVIM STARTED ---
        024.190  000.004: --- NVIM STARTED ---
        024.195  000.003: --- NVIM STARTED ---
        024.210  000.003: --- NVIM STARTED ---
        024.235  000.003: --- NVIM STARTED ---
        024.265  000.004: --- NVIM STARTED ---
        024.268  000.003: --- NVIM STARTED ---
        024.276  000.004: --- NVIM STARTED ---
        024.292  000.003: --- NVIM STARTED ---
        024.300  000.004: --- NVIM STARTED ---
        024.313  000.003: --- NVIM STARTED ---
        024.319  000.004: --- NVIM STARTED ---
        024.330  000.004: --- NVIM STARTED ---
        024.368  000.004: --- NVIM STARTED ---
        024.373  000.003: --- NVIM STARTED ---
        024.375  000.003: --- NVIM STARTED ---
        024.376  000.014: --- NVIM STARTED ---
        024.386  000.003: --- NVIM STARTED ---
        024.387  000.003: --- NVIM STARTED ---
        024.392  000.004: --- NVIM STARTED ---
        024.406  000.003: --- NVIM STARTED ---
        024.415  000.004: --- NVIM STARTED ---
        024.417  000.003: --- NVIM STARTED ---
        024.439  000.003: --- NVIM STARTED ---
        024.540  000.011: --- NVIM STARTED ---
        024.547  000.003: --- NVIM STARTED ---
        024.570  000.003: --- NVIM STARTED ---
        024.611  000.004: --- NVIM STARTED ---
        024.615  000.003: --- NVIM STARTED ---
        024.626  000.003: --- NVIM STARTED ---
        024.631  000.004: --- NVIM STARTED ---
        024.641  000.003: --- NVIM STARTED ---
        024.686  000.003: --- NVIM STARTED ---
        024.710  000.003: --- NVIM STARTED ---
        024.737  000.003: --- NVIM STARTED ---
        024.739  000.003: --- NVIM STARTED ---
        024.755  000.004: --- NVIM STARTED ---
        024.771  000.004: --- NVIM STARTED ---
        024.782  000.003: --- NVIM STARTED ---
        024.814  000.003: --- NVIM STARTED ---
        024.831  000.004: --- NVIM STARTED ---
        024.861  000.003: --- NVIM STARTED ---
        024.876  000.003: --- NVIM STARTED ---
        024.878  000.003: --- NVIM STARTED ---
        024.887  000.003: --- NVIM STARTED ---
        024.911  000.004: --- NVIM STARTED ---
        024.935  000.004: --- NVIM STARTED ---
        024.957  000.004: --- NVIM STARTED ---
        024.959  000.003: --- NVIM STARTED ---
        024.960  000.005: --- NVIM STARTED ---
        024.961  000.003: --- NVIM STARTED ---
        025.002  000.003: --- NVIM STARTED ---
        025.051  000.003: --- NVIM STARTED ---
        025.070  000.004: --- NVIM STARTED ---
        025.345  000.003: --- NVIM STARTED ---
        025.365  000.004: --- NVIM STARTED ---
        025.888  000.003: --- NVIM STARTED ---
        025.944  000.004: --- NVIM STARTED ---
        027.106  000.003: --- NVIM STARTED ---

        Mean:  2433.31 / 100 = 24.3331
      ```

    </details>
