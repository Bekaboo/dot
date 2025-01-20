local icons = require('utils.static.icons')
local boxes = require('utils.static.boxes')
local quicker = require('quicker')

quicker.setup({
  use_default_opts = false,
  keys = {
    {
      'g>',
      function()
        quicker.expand({
          before = 2,
          after = 2,
          add_to_existing = true,
        })
      end,
      desc = 'Expand quickfix context',
    },
    {
      'g<',
      quicker.collapse,
      desc = 'Collapse quickfix context',
    },
  },
  type_icons = {
    E = vim.g.has_nf and icons.DiagnosticSignError or 'ERROR',
    W = vim.g.has_nf and icons.DiagnosticSignWarn or 'WARN',
    I = vim.g.has_nf and icons.DiagnosticSignInfo or 'INFO',
    N = vim.g.has_nf and icons.DiagnosticSignHint or 'NOTE',
    H = vim.g.has_nf and icons.DiagnosticSignHint or 'HINT',
  },
  borders = {
    vert = vim.go.tgc and ' ' or boxes.single.vt,
    -- Strong headers separate results from different files
    strong_header = boxes.single.hr,
    strong_cross = vim.go.tgc and boxes.single.hr or boxes.single.x,
    strong_end = vim.go.tgc and boxes.single.hr or boxes.single.xr,
    -- Soft headers separate results within the same file
    soft_header = boxes.single.hr,
    soft_cross = vim.go.tgc and boxes.single.hr or boxes.single.x,
    soft_end = vim.go.tgc and boxes.single.hr or boxes.single.xr,
  },
  max_filename_width = function()
    return math.ceil(vim.go.columns / 2)
  end,
})
