local icons = require('utils.static').icons

require('nvim-web-devicons').setup({
  override = {
    default_icon = {
      color = '#7c888c',
      cterm_color = '66',
      icon = vim.trim(icons.File),
      name = 'Default',
    },
    desktop = {
      color = '#997bca',
      cterm_color = '60',
      icon = vim.trim(icons.Desktop),
      name = 'DesktopEntry',
    },
    lock = {
      color = '#bbbbbb',
      cterm_color = '250',
      icon = vim.trim(icons.Lock),
      name = 'Lock',
    },
    git = {
      color = '#e84d31',
      cterm_color = '196',
      icon = vim.trim(icons.Git),
      name = 'GitLogo',
    },
    commit_editmsg = {
      color = '#e84d31',
      cterm_color = '239',
      icon = vim.trim(icons.Git),
      name = 'GitCommit',
    },
    pdf = {
      color = '#d65d0e',
      cterm_color = '166',
      icon = vim.trim(icons.Pdf),
      name = 'Pdf',
    },
  },
  override_by_extension = {
    asm = {
      color = '#d65050',
      cterm_color = '167',
      icon = vim.trim(icons.Assembly),
      name = 'Assembly',
    },
    s = {
      color = '#d65050',
      cterm_color = '167',
      icon = vim.trim(icons.Assembly),
      name = 'S',
    },
    S = {
      color = '#d65050',
      cterm_color = '167',
      icon = vim.trim(icons.Assembly),
      name = 'S',
    },
    o = {
      color = '#88a0a7',
      cterm_color = '66',
      icon = vim.trim(icons.Object),
      name = 'O',
    },
    bak = {
      color = '#6d8086',
      cterm_color = '66',
      icon = vim.trim(icons.Bak),
      name = 'Bak',
    },
    cu = {
      color = '#76b900',
      cterm_color = '2',
      icon = vim.trim(icons.Cuda),
      name = 'Cuda',
    },
    raw = {
      color = '#ff9800',
      cterm_color = '208',
      icon = vim.trim(icons.Raw),
      name = 'Raw',
    },
    dat = {
      color = '#6dcde8',
      cterm_color = '81',
      icon = vim.trim(icons.Data),
      name = 'Data',
    },
    pickle = {
      color = '#ffbc03',
      cterm_color = '214',
      icon = vim.trim(icons.Data),
      name = 'Pickle',
    },
    el = {
      color = '#a374ea',
      cterm_color = '61',
      icon = vim.trim(icons.Elisp),
      name = 'Elisp',
    },
    patch = {
      color = '#e84d31',
      cterm_color = '166',
      icon = vim.trim(icons.Git),
      name = 'Patch',
    },
    md = {
      color = '#6fb5ca',
      cterm_color = '74',
      icon = vim.trim(icons.Markdown),
      name = 'Md',
    },
    mdx = {
      color = '#6fb5ca',
      cterm_color = '74',
      icon = vim.trim(icons.Markdown),
      name = 'Mdx',
    },
    markdown = {
      color = '#6fb5ca',
      cterm_color = '74',
      icon = vim.trim(icons.Markdown),
      name = 'Markdown',
    },
    tar = {
      color = '#e84d31',
      cterm_color = '166',
      icon = vim.trim(icons.Zip),
      name = 'Tar',
    },
    zip = {
      color = '#e84d31',
      cterm_color = '166',
      icon = vim.trim(icons.Zip),
      name = 'Zip',
    },
    gz = {
      color = '#e84d31',
      cterm_color = '166',
      icon = vim.trim(icons.Zip),
      name = 'gz',
    },
    ['7z'] = {
      color = '#e84d31',
      cterm_color = '166',
      icon = vim.trim(icons.Zip),
      name = '7z',
    },
    rar = {
      color = '#e84d31',
      cterm_color = '166',
      icon = vim.trim(icons.Zip),
      name = 'Zip',
    },
    theme = {
      color = '#7c9fd5',
      cterm_color = '39',
      icon = vim.trim(icons.Theme),
      name = 'Theme',
    },
    colorscheme = {
      color = '#7c9fd5',
      cterm_color = '39',
      icon = vim.trim(icons.Theme),
      name = 'ColorScheme',
    },
    profile = {
      color = '#6d8086',
      cterm_color = '66',
      icon = vim.trim(icons.Config),
      name = 'Profile',
    },
    rc = {
      color = '#6d8086',
      cterm_color = '66',
      icon = vim.trim(icons.Config),
      name = 'Rc',
    },
    jar = {
      color = '#cc3e44',
      cterm_color = '167',
      icon = vim.trim(icons.Java),
      name = 'Jar',
    },
    mp4 = {
      color = '#FD971F',
      cterm_color = '208',
      icon = vim.trim(icons.Video),
      name = 'Mp4',
    },
    mov = {
      color = '#FD971F',
      cterm_color = '208',
      icon = vim.trim(icons.Video),
      name = 'MOV',
    },
    m4v = {
      color = '#FD971F',
      cterm_color = '208',
      icon = vim.trim(icons.Video),
      name = 'M4V',
    },
    mkv = {
      color = '#FD971F',
      cterm_color = '208',
      icon = vim.trim(icons.Video),
      name = 'Mkv',
    },
    webm = {
      color = '#FD971F',
      cterm_color = '208',
      icon = vim.trim(icons.Video),
      name = 'Webm',
    },
    avi = {
      color = '#fd6c40',
      cterm_color = '208',
      icon = vim.trim(icons.Video),
      name = 'AVI',
    },
    ipynb = {
      color = '#f27726',
      cterm_color = '166',
      icon = vim.trim(icons.Ipynb),
      name = 'Ipynb',
    },
    ppt = {
      icon = '󰈧',
      color = '#cb4a32',
      cterm_color = '160',
      name = 'Ppt',
    },
    pptx = {
      icon = '󰈧',
      color = '#cb4a32',
      cterm_color = '160',
      name = 'Pptx',
    },
  },
  override_by_filename = {
    run_datasets = {
      color = '#65767a',
      cterm_color = '238',
      icon = vim.trim(icons.Sh),
      name = 'ShellRunDatasets',
    },
    configure = {
      color = '#6d8086',
      cterm_color = '66',
      icon = vim.trim(icons.Config),
      name = 'Configure',
    },
    ['package.json'] = {
      color = '#bbbbbb',
      cterm_color = '250',
      icon = vim.trim(icons.Lock),
      name = 'PackageJson',
    },
    ['package-lock.json'] = {
      color = '#bbbbbb',
      cterm_color = '250',
      icon = vim.trim(icons.Lock),
      name = 'PackageLockJson',
    },
    ['.luacheckrc'] = {
      color = '#6d8086',
      cterm_color = '66',
      icon = vim.trim(icons.Config),
      name = 'LuaCheckRc',
    },
    ['.gitattributes'] = {
      color = '#e84d31',
      cterm_color = '239',
      icon = vim.trim(icons.Git),
      name = 'GitAttributes',
    },
    ['.gitconfig'] = {
      color = '#e84d31',
      cterm_color = '239',
      icon = vim.trim(icons.Git),
      name = 'GitConfig',
    },
    ['.gitignore'] = {
      color = '#e84d31',
      cterm_color = '239',
      icon = vim.trim(icons.Git),
      name = 'GitIgnore',
    },
    ['.gitmodules'] = {
      color = '#e84d31',
      cterm_color = '239',
      icon = vim.trim(icons.Git),
      name = 'GitModules',
    },
  },
})
