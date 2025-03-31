## Neovim :: M Λ C R O

[**Neovim :: M Λ C R O**](./) is a collection of neovim configuration files inspired
by [Emacs / N Λ N O](https://github.com/rougier/nano-emacs).

The goal of macro-neovim is to provide a clean and elegant user interface
while remaining practical for daily tasks, striking a balance between a
streamlined design and effective functionality. See [showcases](#showcases) to
get a glimpse of the basic usage and what this configuration looks like.

This is a highly personalized and opinionated neovim configuration, not a
distribution. While it's not meant for direct use, you're welcome to fork,
experiment, and adapt it to your liking. Feel free to use it as a starting
point for your configuration or borrow elements you find useful. Issues and PRs
are welcome.

Currently only tested on Linux (X11/Wayland/TTY) and Android (Termux).

<center>
    <img src="https://github.com/Bekaboo/nvim/assets/76579810/299137e7-9438-489b-b98b-7211a62678ae" width=46%>  
    <img src="https://github.com/Bekaboo/nvim/assets/76579810/9e546e33-7678-47e2-8a80-368d7c59534a" width=46%>
</center>

## Table of Contents

<!--toc:start-->
- [Features](#features)
- [Requirements and Dependencies](#requirements-and-dependencies)
  - [Basic](#basic)
  - [Tree-sitter](#tree-sitter)
  - [LSP](#lsp)
  - [DAP](#dap)
  - [Formatter](#formatter)
- [Installation](#installation)
- [Troubleshooting](#troubleshooting)
- [Performance](#performance)
  - [Big Files](#big-files)
- [Uninstallation](#uninstallation)
- [Config Structure](#config-structure)
- [Tweaking this Configuration](#tweaking-this-configuration)
  - [Managing Plugins with Modules](#managing-plugins-with-modules)
  - [Installing Packages to an Existing Module](#installing-packages-to-an-existing-module)
  - [Installing Packages to a New Module](#installing-packages-to-a-new-module)
  - [General Settings and Options](#general-settings-and-options)
  - [Environment Variables](#environment-variables)
  - [Keymaps](#keymaps)
  - [Colorschemes](#colorschemes)
  - [Auto Commands](#auto-commands)
  - [LSP Server Configurations](#lsp-server-configurations)
  - [DAP Configurations](#dap-configurations)
  - [Snippets](#snippets)
  - [Enabling VSCode Integration](#enabling-vscode-integration)
- [Appendix](#appendix)
  - [Showcases](#showcases)
  - [Default Modules and Plugins of Choice](#default-modules-and-plugins-of-choice)
    - [Third Party Plugins](#third-party-plugins)
    - [Builtin Plugins](#builtin-plugins)
  - [Startuptime](#startuptime)
<!--toc:end-->

## Features

- Modular design
    - Install and manage packages in groups
    - Make it easy to use different set of configuration for different use
      cases
- Clean and uncluttered UI, including customized versions of:
    - [winbar](lua/plugin/winbar)
    - [statusline](lua/plugin/statusline.lua)
    - [statuscolumn](lua/plugin/statuscolumn.lua)
    - [colorschemes](colors)
    - [intro message](plugin/intro.lua)
- [VSCode-Neovim](https://github.com/vscode-neovim/vscode-neovim) integration, makes you feel at home in VSCode when you
  occasionally need it
- Massive [TeX math snippets](lua/snippets/shared/math.lua)
- Jupyter Notebook integration: edit notebooks like markdown files, run code in
  cells with simple commands and shortcuts
- Optimization for large files, open any file larger than 100 MB and edit like
  butter (see [big files](#big-files))
- Fast startup around [~25 ms](#startuptime)

## Requirements and Dependencies

### Basic

- [Neovim](https://github.com/neovim/neovim) 0.11, for exact version see [nvim-version.txt](nvim-version.txt)
- [Git](https://git-scm.com/)
- [GCC](https://gcc.gnu.org/) or [Clang](https://clang.llvm.org/) for building treesitter parsers and some libs
- [Fd](https://github.com/sharkdp/fd), [Ripgrep](https://github.com/BurntSushi/ripgrep), and [Fzf](https://github.com/junegunn/fzf) for fuzzy search
- [Pandoc](https://pandoc.org/), [custom scripts](../../.bin) and [TexLive](https://www.tug.org/texlive/) (for ArchLinux users, it is `texlive-core` and `texlive-extra`) for markdown → PDF conversion (`:MarkdownToPDF`)
- [Node.js](https://nodejs.org/en) for installing dependencies for [markdown-preview.nvim](https://github.com/iamcco/markdown-preview.nvim)
- [Pynvim](https://github.com/neovim/pynvim), [Jupyter Client](https://github.com/jupyter/jupyter_client), and [IPython Kernel](https://github.com/ipython/ipykernel) for Python support
- [Jupytext](https://github.com/mwouts/jupytext) for editing Jupyter notebooks
- A decent terminal emulator
- A nerd font, e.g. [JetbrainsMono Nerd Font](https://github.com/ryanoasis/nerd-fonts/tree/master/patched-fonts/JetBrainsMono).
  This is optional as nerd icons are disabled by default, to enable it, set the
  environment variable `$NVIM_NF`, see [environment variables](#environment-variables)

### Tree-sitter

Tree-sitter installation and configuration are handled by [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter).

Requires a C compiler, e.g. [GCC](https://gcc.gnu.org/) or [Clang](https://clang.llvm.org/), for building parsers.

To add or remove support for a language, install or uninstall the corresponding
parser using `:TSInstall` or `:TSUninstall`.

To make the change permanent, add or remove corresponding parsers in the
`ensure_installed` field in the call to nvim-treesitter's `setup()` function,
see [lua/configs/nvim-treesitter.lua](lua/configs/nvim-treesitter.lua).

### LSP

For LSP support, install the following language servers manually using your
favorite package manager:

- Bash: [BashLS](https://github.com/bash-lsp/bash-language-server)

    Example for ArchLinux users:

    ```sh
    sudo pacman -S bash-language-server
    ```

- C/C++: [Clang](https://clang.llvm.org/)
- Lua: [LuaLS](https://github.com/LuaLS/lua-language-server)
- Python: one of
    - [Jedi Language Server](https://github.com/pappasam/jedi-language-server)
    - [Python LSP Server](https://github.com/python-lsp/python-lsp-server)
    - [Pyright](https://github.com/microsoft/pyright)
- Rust: [Rust Analyzer](https://rust-analyzer.github.io/)
- LaTeX: [TexLab](https://github.com/latex-lsp/texlab)
- VimL: [VimLS](https://github.com/iamcco/vim-language-server)
- Markdown: [Marksman](https://github.com/artempyanykh/marksman)
- Go: [Gopls](https://github.com/golang/tools/tree/master/gopls)
- Typescript: [Typescript Language Server](https://github.com/typescript-language-server/typescript-language-server) and [Biome](https://biomejs.dev/) 
- General-purpose language server: [EFM Language Server](https://github.com/mattn/efm-langserver)
    - Already configured for
        - [Black](https://github.com/psf/black) (formatter)
        - [Shfmt](https://github.com/mvdan/sh) (formatter)
        - [Fish-indent](https://fishshell.com/docs/current/cmds/fish_indent.html) (formatter)
        - [StyLua](https://github.com/JohnnyMorganz/StyLua) (formatter)
        - [Gofmt](https://pkg.go.dev/cmd/gofmt) (formatter)
        - [Golangcli-lint](https://github.com/golangci/golangci-lint) (linter)
        - [Prettier](https://prettier.io/) (formatter)
        - [Eslint](https://eslint.org/) (linter)
        - ...

To add support for other languages, install corresponding language servers
manually then add `lsp.lua` files under [after/ftplugin](after/ftplugin) to automatically launch
them for different filetypes.

Some examples of `lsp.lua` files:

- [after/ftplugin/lua/lsp.lua](after/ftplugin/lua/lsp.lua)
- [after/ftplugin/python/lsp.lua](after/ftplugin/python/lsp.lua)
- [after/ftplugin/rust/lsp.lua](after/ftplugin/rust/lsp.lua)
- [after/ftplugin/sh/lsp.lua](after/ftplugin/sh/lsp.lua)
- [after/ftplugin/go/lsp.lua](after/ftplugin/go/lsp.lua)
- [after/ftplugin/typescript/lsp.lua](after/ftplugin/typescript/lsp.lua)

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

    or in a virtual env:

    ```sh
    pip install debugpy
    ```

- Go: install [Delve](https://github.com/go-delve/delve)

For more information on DAP installation, see [Debug Adapter Installation](https://github.com/mfussenegger/nvim-dap/wiki/Debug-Adapter-installation).

### Formatter

- Bash: install [Shfmt](https://github.com/mvdan/sh)\*
- C/C++: install [Clang](https://clang.llvm.org/) to use `clang-format`
- Lua: install [StyLua](https://github.com/JohnnyMorganz/StyLua)\*
- Rust: install [Rust](https://www.rust-lang.org/tools/install) to use `rustfmt`
- Python: install [Black](https://github.com/psf/black)\*
- LaTeX: install [texlive-core](http://tug.org/texlive/) to use `latexindent`

<sub>\*Need [EFM Language Server](https://github.com/mattn/efm-langserver) to work with `vim.lsp.buf.format()`</sub>

## Installation

1. Make sure you have required dependencies installed.
2. Clone this repo to your config directory

    ```sh
    git clone https://github.com/Bekaboo/dot.git bkb_dot && cp -r bkb_dot/.config/nvim ~/.config/nvim.macro
    ```

4. Open neovim using 

    ```sh
    NVIM_APPNAME=nvim.macro nvim
    ```

    On first installation, neovim will prompt you to decide whether to install
    third-party plugins, press `y` to install, `n` to skip, `never` to skip and
    disable the prompt in the future (aka "do not ask again").

    The suggestion is to use `n` to skip installing plugins on first launch,
    and see if everything works OK under a bare minimum setup. Depending on
    your needs, you can choose whether to install third-party plugins later
    using `y`/`yes` or `never` on the second launch.

    **Some notes about third-party plugins**

    Installing third-party plugins is known to cause issues in some cases,
    including:

    1. Partially cloned plugins and missing dependencies due to slow network
       connection
    2. Building failure especially for plugins like [telescope-fzf-native.nvim](https://github.com/nvim-telescope/telescope-fzf-native.nvim)
       and [markdown-preview.nvim](https://github.com/iamcco/markdown-preview.nvim) due to missing building dependencies or slow
       installation process
    3. Treesitter plugins can easily cause issues if you are on a different
       nvim version, check [nvim-version.txt](nvim-version.txt) for the version of nvim targeted by
       this config

    To avoid these issues,

    1. Ensure you have a fast network before installing third-party plugins
    2. If the building process failed, go to corresponding project directory
       under `g:package_path` and manually run the build command from there.
       The build commands are declared in module specification files under
       [lua/modules](lua/modules)
    3. Ensure you are on the same version of nvim as specified in
       [nvim-version.txt](nvim-version.txt) if you encounter any issue related to treesitter

5. After entering neovim, Run `:checkhealth` to check potential dependency
   issues.
6. Enjoy!

## Troubleshooting

If you encounter any issue, please try the following steps:

1. Run `:Lazy restore` once to ensure that all packages are properly
   installed
2. Run `:checkhealth` to check potential dependency issues
3. Check `:version` to make sure you are on the same (of above) version of
   neovim as specified in [nvim-version.txt](nvim-version.txt)
4. Try removing the following paths then restart neovim:
    - `:echo stdpath('cache')`
    - `:echo stdpath('state')`
    - `:echo stdpath('data')`
5. If still not working, please open an issue and I will be happy to help

## Performance

Use the following steps to generate a flamegraph to troubleshoot performance
issues, e.g. laggy when typing or scrolling (requires
[FlameGraphs](https://www.brendangregg.com/flamegraphs.html) to be installed):

1. Inside neovim, run `:lua require('jit.p').start('10,i1,s,m0,G', '/tmp/nvim-profile.log')`
2. Reproduce the performance issue
3. `:lua require('jit.p').stop()`
4. `:qa!`
5. `flamegraph.pl /tmp/nvim-profile.log > /tmp/nvim-profile-flamegraph.svg && firefox /tmp/nvim-profile-flamegraph.svg`

### Big Files

Customize how neovim determines large files by adjusting these settings:

- `vim.g.bigfile_max_lines`
    - Default: `32768`
    - Buffers with number of lines exceeding this will be flagged as big file
- `vim.g.bigfile_max_size`
    - Default: `1048576` (bytes)
    - Buffers with corresponding file size exceeding this will be flagged as
      big file

When a file is flagged as a big file (`vim.b.bigfile` is set), certain features
will be disabled to improve performance.

## Uninstallation

You can uninstall this config completely by simply removing the following
paths:

- `:echo stdpath('config')`
- `:echo stdpath('cache')`
- `:echo stdpath('state')`
- `:echo stdpath('data')`

## Config Structure

```
.
├── colors                      # colorschemes
├── plugin                      # custom plugins
├── ftplugin                    # custom filetype plugins
├── init.lua                    # entry of config
├── lua
│   ├── core                    # files under this folder is required by 'init.lua'
│   │   ├── autocmds.lua
│   │   ├── opts.lua            # options and general settings
│   │   ├── keymaps.lua
│   │   └── modules.lua         # bootstraps plugin manager and specifies which modules to include
│   ├── modules                 # all plugin specifications and configs go here
│   │   ├── ui.lua              # ui elements, e.g. icons
│   │   ├── completion.lua      # auto-completion
│   │   ├── debug.lua           # debug adapter (DAP) support
│   │   ├── edit.lua            # general editing enhancements, e.g. auto-pair, surround, align, etc.
│   │   ├── langs.lua           # language-specific plugins
│   │   ├── llm.lua             # completion and code generators using LLMs
│   │   ├── markup.lua          # enhancement for markdown and tex editing
│   │   ├── tools.lua           # tools like fuzzy finder, git integration, etc.
│   │   ├── treesitter.lua      # treesitter related plugins
│   │   └── colorschemes.lua    # third-party themes
│   ├── configs                 # configs for each plugin
│   ├── snippets                # snippets
│   ├── plugin                  # the actual implementation of custom plugins
│   └── utils
└── syntax                      # syntax files
```

## Tweaking this Configuration

### Managing Plugins with Modules

In order to enable or disable a module, one need to change the table in
[lua/core/modules.lua](lua/core/modules.lua) passed to `enable_modules()`, for example

```lua
enable_modules({
  'treesitter',
  'edit',
  -- ...
})
```

### Installing Packages to an Existing Module

To install plugin `foo` under module `bar`, just insert the corresponding
specification to the big table `lua/modules/bar.lua` returns, for instance,

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
create module `bar` under [lua/modules](lua/modules):

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

After creating the new module `bar`, enable it in [lua/core/modules.lua](lua/core/modules.lua):

```lua
enable_modules({
  -- ...
  'bar',
  -- ...
})
```

### General Settings and Options

See [lua/core/opts.lua](lua/core/opts.lua).

### Environment Variables

- `$NVIM_NO3RD`: disable third-party plugins if set
- `$NVIM_NF`: enable nerd font icons if set

### Keymaps

See [lua/core/keymaps.lua](lua/core/keymaps.lua), or see [module config files](lua/configs) for
corresponding plugin keymaps.

### Colorschemes

`cockatoo`, `nano`, `macro`, and `sonokai` are three builtin custom
colorschemes, with separate palettes for dark and light background.

Neovim is configured to restore the previous background and colorscheme
settings on startup, so there is no need to set them up in the config file
explicitly.

To disable the auto-restore feature, remove the `ColorSchemeRestore` augroup
in [lua/core/autocmds.lua](lua/core/autocmds.lua).

To tweak a colorscheme, edit corresponding colorscheme files under [colors](colors).

### Auto Commands

See [lua/core/autocmds.lua](lua/core/autocmds.lua).

### LSP Server Configurations

See [lua/utils/lsp.lua](lua/utils/lsp.lua) and `lsp.lua` files under [after/ftplugin](after/ftplugin).

### DAP Configurations

See [lua/configs/dap-configs](lua/configs/dap-configs), [lua/configs/nvim-dap.lua](lua/configs/nvim-dap.lua), and [lua/configs/nvim-dap-ui.lua](lua/configs/nvim-dap-ui.lua).

### Snippets

This configuration use [LuaSnip](https://github.com/L3MON4D3/LuaSnip) as the snippet engine,
custom snippets for different filetypes
are defined under [lua/snippets](lua/snippets).

### Enabling VSCode Integration

VSCode integration takes advantages of the modular design, allowing to use
a different set of modules when neovim is launched by VSCode, relevant code is
in [autoload/plugin/vscode.vim](autoload/plugin/vscode.vim) and [lua/core/modules.lua](lua/core/modules.lua).

To make VSCode integration work, please install [VSCode-Neovim](https://github.com/vscode-neovim/vscode-neovim) in VSCode
and configure it correctly.

After setting up VSCode-Neovim, re-enter VSCode, open a random file
and it should work out of the box.

## Appendix

### Showcases

- File manager using [oil.nvim](https://github.com/stevearc/oil.nvim)<br>
    <img src="https://github.com/Bekaboo/nvim/assets/76579810/26bb146f-7637-4f68-acd7-baecc08f1eaf" width=75%>

- DAP support powered by [nvim-dap](https://github.com/mfussenegger/nvim-dap) and [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui)<br>
    <img src="https://github.com/Bekaboo/nvim/assets/76579810/f6c7e6ce-283b-43d7-8bc3-e8b24513a03b" width=75%>

- Jupyter Notebook integration using [jupytext](lua/plugin/jupytext.lua) and [molten-nvim](https://github.com/benlubas/molten-nvim)<br>
    <img src="https://github.com/Bekaboo/nvim/assets/76579810/ce212348-8b89-4a03-a222-ab74f0338a7d" width=75%>

- Winbar with IDE-like drop-down menus using [dropbar.nvim](https://github.com/Bekaboo/dropbar.nvim)<br>
    <img src="https://github.com/Bekaboo/nvim/assets/76579810/247401a9-6127-4d73-bb21-ceb847d8f7b9" width=75%>

- LSP hover & completion thanks to neovim builtin LSP client and [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)<br>
    <img src="https://github.com/Bekaboo/nvim/assets/76579810/13589137-b5c7-4104-810c-f8cdc56f9d1b" width=75%>
    <img src="https://github.com/Bekaboo/nvim/assets/76579810/60c5b599-4191-494d-ad83-1ca7a84eab17" width=75%>

- Git integration: [fugitive](https://github.com/tpope/vim-fugitive) and [gitsigns.nvim](https://github.com/tpope/vim-fugitive)<br>
    <img src="https://github.com/Bekaboo/nvim/assets/76579810/a5e0a41d-4e85-4bfc-a39d-cc7b76abedcf" width=75%>
    <img src="https://github.com/Bekaboo/nvim/assets/76579810/73da4ee1-8f6c-440a-9eb9-0bcf3bc8e3ea" width=75%>

### Default Modules and Plugins of Choice

#### Third Party Plugins


- **UI**
    - [nvim-web-devicons](https://github.com/kyazdani42/nvim-web-devicons)
- **Completion**
    - [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)
    - [cmp-calc](https://github.com/hrsh7th/cmp-calc)
    - [cmp-cmdline](https://github.com/hrsh7th/cmp-cmdline)
    - [cmp-path](https://github.com/hrsh7th/cmp-path)
    - [cmp-nvim-lsp](https://github.com/hrsh7th/cmp-nvim-lsp)
    - [cmp-buffer](https://github.com/hrsh7th/cmp-buffer)
    - [cmp_luasnip](https://github.com/saadparwaiz1/cmp_luasnip)
    - [cmp-nvim-lsp-signature-help](https://github.com/hrsh7th/cmp-nvim-lsp-signature-help)
    - [cmp-dap](https://github.com/rcarriga/cmp-dap)
    - [LuaSnip](https://github.com/L3MON4D3/LuaSnip)
 - **LLM**
    - [codecompanion.nvim](https://github.com/olimorris/codecompanion.nvim)
- **Markup**
    - [vimtex](https://github.com/lervag/vimtex)
    - [markdown-preview.nvim](https://github.com/iamcco/markdown-preview.nvim)
    - [vim-table-mode](https://github.com/dhruvasagar/vim-table-mode)
    - [otter.nvim](https://github.com/jmbuhr/otter.nvim)
    - [molten-nvim](https://github.com/benlubas/molten-nvim)
    - [img-clip.nvim](https://github.com/HakonHarnes/img-clip.nvim)
- **Edit**
    - [nvim-surround](https://github.com/kylechui/nvim-surround)
    - [vim-sleuth](https://github.com/tpope/vim-sleuth)
    - [ultimate-autopairs.nvim](https://github.com/altermo/ultimate-autopair.nvim)
    - [vim-easy-align](https://github.com/junegunn/vim-easy-align)
- **Tools**
    - [fzf-lua](https://github.com/ibhagwan/fzf-lua)
    - [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim)
        - [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) (dependency)
    - [vim-fugitive](https://github.com/tpope/vim-fugitive)
        - [vim-rhubarb](https://github.com/tpope/vim-rhubarb) (dependency)
        - [fugitive-gitlab.vim](https://github.com/shumphrey/fugitive-gitlab.vim) (dependency)
    - [oil.nvim](https://github.com/stevearc/oil.nvim)
    - [quicker.nvim](https://github.com/stevearc/quicker.nvim)
    - [which-key.nvim](https://github.com/folke/which-key.nvim)
- **LSP**
    - [clangd_extensions.nvim](https://github.com/p00f/clangd_extensions.nvim)
- **Treesitter**
    - [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
    - [nvim-treesitter-textobjects](https://github.com/nvim-treesitter/nvim-treesitter-textobjects)
    - [nvim-treesitter-endwise](https://github.com/RRethy/nvim-treesitter-endwise)
    - [ts-autotag.nvim](https://github.com/tronikelis/ts-autotag.nvim)
    - [treesj](https://github.com/Wansmer/treesj)
    - [cellular-automaton.nvim](https://github.com/Eandrju/cellular-automaton.nvim)
- **Debug**
    - [nvim-dap](https://github.com/mfussenegger/nvim-dap)
    - [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui)
        - [nvim-nio](https://github.com/nvim-neotest/nvim-nio) (dependency)
    - [one-small-step-for-vimkind](https://github.com/jbyuki/one-small-step-for-vimkind)
- **Colorschemes**
    - [everforest](https://github.com/sainnhe/everforest)
    - [gruvbox-material](https://github.com/sainnhe/gruvbox-material)

#### Builtin Plugins

- [colorcolumn](plugin/colorcolumn.lua)
    - Shows color column dynamically based on current line width
    - Released as [deadcolumn.nvim](https://github.com/Bekaboo/deadcolumn.nvim)
- [expandtab](lua/plugin/expandtab.lua)
    - Always use spaces for alignment, even if `'expandtab'` is not set, see
      `:h 'tabstop'` point 5
- [fcitx5](lua/plugin/fcitx5.lua)
    - Switches and restores fcitx5 state in each buffer asynchronously
- [jupytext](lua/plugin/jupytext.lua)
    - Edits jupyter notebook like markdown files
    - Writes into jupyter notebook asynchronously, which gives a smoother
      experience than [jupytext.vim](https://github.com/goerz/jupytext)
- [intro](plugin/intro.lua)
    - Shows a custom intro message on startup
- [lsp](lua/plugin/lsp.lua)
    - Sets up LSP and diagnostic options and commands on `LspAttach` or
      `DiagnosticChanged`
- [readline](lua/plugin/readline.lua)
    - Readline-like keybindings in insert and command mode
- [statuscolumn](lua/plugin/statuscolumn.lua)
    - Custom statuscolumn, with git signs on the right of line numbers
- [statusline](lua/plugin/statusline.lua)
    - Custom statusline inspired by [nano-emacs](https://github.com/rougier/nano-emacs)
- [tabline](lua/plugin/tabline.lua)
    - Simple tabline that shows the current working directory of each tab
    - Use `:[count]TabRename [name]` to rename tabs
- [tabout](lua/plugin/tabout.lua)
    - Tab out and in with `<Tab>` and `<S-Tab>`
- [term](lua/plugin/term.lua)
    - Some nice setup for terminal buffers
- [tmux](lua/plugin/tmux.lua)
    - Integration with tmux, provides unified keymaps for navigation, resizing,
      and many other window operations
- [vscode](autoload/plugin/vscode.vim)
    - Integration with [VSCode-Neovim](https://github.com/vscode-neovim/vscode-neovim)
- [winbar](lua/plugin/winbar.lua)
    - A winbar with drop-down menus and multiple backends
    - Released as [dropbar.nvim](https://github.com/Bekaboo/dropbar.nvim)
- [markdown-title](after/ftplugin/markdown/title.lua)
    - Automatically capitalize the first letter of each word in markdown titles
    - Use `:MarkdownAutoFormatTitle enable/disable` to enable or disable this
      feature
- [markdown-codeblock](after/ftplugin/markdown/codeblock.lua)
    - Add shadings to markdown code blocks
- [z](lua/plugin/z.lua)
    - Jump between frequently visited directories with `:Z` command using
      [z.lua](https://github.com/skywind3000/z.lua),
      [z.fish](https://github.com/jethrokuan/z), or
      [zoxide](https://https://github.com/ajeetdsouza/zoxide)
- [addasync](lua/plugin/addasync.lua)
    - Automatically add `async` to python/javascript/typescript functions
      containing `await`

Like many vim builtin plugins, these plugins can be disabled by setting the
`g:loaded_...` flag before loading them.

### Startuptime

- Neovim Version:

    ```
    NVIM v0.10.4
    Build type: RelWithDebInfo
    LuaJIT 2.1.1731601260
    Run "nvim -V1 -v" for more info
    ```

- Config Commit: `4ba45170`

- System: Arch Linux 6.12.10

- Machine: ThinkPad X1 Nano Gen 1

- Startup time with `--clean`:

    ```sh
    hyperfine -Nw10 'nvim --clean +q'
    ```

    ```
    Benchmark 1: nvim --clean +q
      Time (mean ± σ):       7.2 ms ±   1.0 ms    [User: 5.0 ms, System: 2.1 ms]
      Range (min … max):     6.0 ms …  12.5 ms    440 runs
    ```

- Startup time with this config:

    ```sh
    hyperfine -Nw10 'nvim +q'
    ```

    ```
    Benchmark 1: nvim +q
      Time (mean ± σ):       8.8 ms ±   1.1 ms    [User: 6.2 ms, System: 2.4 ms]
      Range (min … max):     7.4 ms …  14.2 ms    362 runs
    ```

    <details>
      <summary>startuptime log</summary>

    ```
    --- Startup times for process: Primary/TUI ---

    times in msec
     clock   self+sourced   self:  sourced script
     clock   elapsed:              other lines

    000.000  000.000: --- NVIM STARTING ---
    000.088  000.087: event init
    000.150  000.062: early init
    000.182  000.033: locale set
    000.217  000.034: init first window
    000.435  000.218: inits 1
    000.439  000.004: window checked
    000.441  000.002: parsing arguments
    000.812  000.028  000.028: require('vim.shared')
    000.869  000.029  000.029: require('vim.inspect')
    000.925  000.048  000.048: require('vim._options')
    000.927  000.113  000.036: require('vim._editor')
    000.928  000.162  000.022: require('vim._init_packages')
    000.930  000.327: init lua interpreter
    001.322  000.392: --- NVIM STARTED ---

    --- Startup times for process: Embedded ---

    times in msec
     clock   self+sourced   self:  sourced script
     clock   elapsed:              other lines

    000.000  000.000: --- NVIM STARTING ---
    000.076  000.075: event init
    000.129  000.053: early init
    000.156  000.027: locale set
    000.186  000.030: init first window
    000.386  000.200: inits 1
    000.393  000.007: window checked
    000.394  000.001: parsing arguments
    000.734  000.025  000.025: require('vim.shared')
    000.792  000.028  000.028: require('vim.inspect')
    000.831  000.030  000.030: require('vim._options')
    000.832  000.096  000.038: require('vim._editor')
    000.833  000.140  000.019: require('vim._init_packages')
    000.834  000.300: init lua interpreter
    000.877  000.042: expanding arguments
    000.889  000.012: inits 2
    001.106  000.217: init highlight
    001.107  000.001: waiting for UI
    001.221  000.114: done waiting for UI
    001.233  000.012: clear screen
    001.282  000.005  000.005: require('vim.keymap')
    001.704  000.469  000.464: require('vim._defaults')
    001.706  000.004: init default mappings & autocommands
    001.968  000.034  000.034: sourcing /usr/share/nvim/runtime/ftplugin.vim
    002.021  000.032  000.032: sourcing /usr/share/nvim/runtime/indent.vim
    002.100  000.047  000.047: sourcing /usr/share/nvim/archlinux.lua
    002.103  000.061  000.013: sourcing /etc/xdg/nvim/sysinit.vim
    002.192  000.032  000.032: require('vim.fs')
    002.455  000.258  000.258: require('vim.uri')
    002.465  000.326  000.036: require('vim.loader')
    002.879  000.404  000.404: require('core.opts')
    002.993  000.112  000.112: require('core.keymaps')
    003.184  000.189  000.189: require('core.autocmds')
    004.016  000.116  000.116: require('vim.ui')
    004.036  000.851  000.735: require('core.modules')
    004.037  001.910  000.028: sourcing /home/zeng/.config/nvim/init.lua
    004.042  000.299: sourcing vimrc file(s)
    004.268  000.032  000.032: sourcing /home/zeng/.config/nvim/filetype.lua
    004.436  000.021  000.021: sourcing /usr/share/vim/vimfiles/ftdetect/meson.vim
    004.456  000.172  000.152: sourcing /usr/share/nvim/runtime/filetype.lua
    004.567  000.051  000.051: sourcing /usr/share/nvim/runtime/syntax/synload.vim
    004.648  000.160  000.109: sourcing /usr/share/nvim/runtime/syntax/syntax.vim
    005.039  000.268  000.268: sourcing /home/zeng/.config/nvim/plugin/_load.lua
    005.161  000.108  000.108: sourcing /home/zeng/.config/nvim/plugin/intro.lua
    005.373  000.016  000.016: sourcing /usr/share/nvim/runtime/plugin/gzip.vim
    005.390  000.007  000.007: sourcing /usr/share/nvim/runtime/plugin/matchit.vim
    005.495  000.087  000.087: sourcing /usr/share/nvim/runtime/plugin/matchparen.vim
    005.513  000.008  000.008: sourcing /usr/share/nvim/runtime/plugin/netrwPlugin.vim
    005.525  000.003  000.003: sourcing /usr/share/nvim/runtime/plugin/rplugin.vim
    005.583  000.038  000.038: sourcing /usr/share/nvim/runtime/plugin/shada.vim
    005.615  000.006  000.006: sourcing /usr/share/nvim/runtime/plugin/spellfile.vim
    005.633  000.007  000.007: sourcing /usr/share/nvim/runtime/plugin/tarPlugin.vim
    005.648  000.005  000.005: sourcing /usr/share/nvim/runtime/plugin/tutor.vim
    005.666  000.009  000.009: sourcing /usr/share/nvim/runtime/plugin/zipPlugin.vim
    005.716  000.041  000.041: sourcing /usr/share/nvim/runtime/plugin/editorconfig.lua
    005.788  000.061  000.061: sourcing /usr/share/nvim/runtime/plugin/man.lua
    005.875  000.075  000.075: sourcing /usr/share/nvim/runtime/plugin/osc52.lua
    005.915  000.027  000.027: sourcing /usr/share/nvim/runtime/plugin/tohtml.lua
    005.993  000.023  000.023: sourcing /usr/share/vim/vimfiles/plugin/black.vim
    006.010  000.008  000.008: sourcing /usr/share/vim/vimfiles/plugin/fzf.vim
    006.024  000.821: loading rtp plugins
    006.096  000.071: loading packages
    006.101  000.005: loading after plugins
    006.109  000.008: inits 3
    006.158  000.049: opening buffers
    006.186  000.005  000.005: require('vim.F')
    006.189  000.026: BufEnter autocommands
    006.190  000.001: editing files in windows
    006.277  000.024  000.024: require('utils')
    006.278  000.071  000.047: require('utils.json')
    006.311  000.027  000.027: require('utils.fs')
    008.283  000.898  000.898: sourcing /home/zeng/.config/nvim/colors/sonokai.lua
    008.389  000.085  000.085: require('utils.hl')
    008.439  001.169: VimEnter autocommands
    008.853  000.017  000.017: require('ffi')
    008.861  000.263  000.246: require('lazy.stats')
    009.132  000.256  000.256: require('lazy.core.util')
    009.318  000.061  000.061: require('vim.highlight')
    009.427  000.408: UIEnter autocommands
    009.429  000.002: before starting main loop
    009.610  000.057  000.057: require('plugin.statuscolumn')
    009.713  000.028  000.028: require('utils.stl')
    010.012  000.242  000.242: require('plugin.statusline')
    010.113  000.065  000.065: require('utils.git')
    010.158  000.037  000.037: require('vim._system')
    010.985  001.127: first screen update
    010.988  000.003: --- NVIM STARTED ---
    ```

    </details>
