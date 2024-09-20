local utils = require('utils')
local icons = utils.static.icons

require('render-markdown').setup({
  render_modes = true,
  signs = { enabled = false },
  bullet = {
    icons = {
      icons.Diamond,
      icons.DotLarge,
      icons.Dot,
    },
    right_pad = 1,
  },
  heading = {
    sign = false,
    width = 'full',
    position = 'inline',
    border = true,
    icons = {
      icons.MarkdownH1,
      icons.MarkdownH2,
      icons.MarkdownH3,
      icons.MarkdownH4,
      icons.MarkdownH5,
      icons.MarkdownH6,
    },
  },
  code = {
    sign = false,
    width = 'block',
    position = 'right',
    language_pad = 2,
    left_pad = 2,
    right_pad = 2,
    border = 'thick',
    above = ' ',
    below = ' ',
  },
})

---Set default highlight groups
---@return nil
local function set_default_hlgroups()
  utils.hl.set(0, 'RenderMarkdownCode', { bg = 'CursorLine' })
  utils.hl.set(0, 'RenderMarkdownBullet', { link = 'markdownListMarker' })
  utils.hl.set(0, 'RenderMarkdownQuote', { link = 'markdownBlockQuote' })
  utils.hl.set(0, 'RenderMarkdownH1', { link = 'markdownH1' })
  utils.hl.set(0, 'RenderMarkdownH2', { link = 'markdownH2' })
  utils.hl.set(0, 'RenderMarkdownH3', { link = 'markdownH3' })
  utils.hl.set(0, 'RenderMarkdownH4', { link = 'markdownH4' })
  utils.hl.set(0, 'RenderMarkdownH5', { link = 'markdownH5' })
  utils.hl.set(0, 'RenderMarkdownH6', { link = 'markdownH6' })

  local normal_bg = utils.hl.get(0, { name = 'Normal', link = false }).bg
  utils.hl.set(0, 'RenderMarkdownH1Bg', {
    bg = utils.hl.cblend(
      utils.hl.get(0, { name = 'RenderMarkdownH1', link = false }).fg,
      normal_bg,
      0.1
    ).hex,
  })
  utils.hl.set(0, 'RenderMarkdownH2Bg', {
    bg = utils.hl.cblend(
      utils.hl.get(0, { name = 'RenderMarkdownH2', link = false }).fg,
      normal_bg,
      0.1
    ).hex,
  })
  utils.hl.set(0, 'RenderMarkdownH3Bg', {
    bg = utils.hl.cblend(
      utils.hl.get(0, { name = 'RenderMarkdownH3', link = false }).fg,
      normal_bg,
      0.1
    ).hex,
  })
  utils.hl.set(0, 'RenderMarkdownH4Bg', {
    bg = utils.hl.cblend(
      utils.hl.get(0, { name = 'RenderMarkdownH4', link = false }).fg,
      normal_bg,
      0.1
    ).hex,
  })
  utils.hl.set(0, 'RenderMarkdownH5Bg', {
    bg = utils.hl.cblend(
      utils.hl.get(0, { name = 'RenderMarkdownH5', link = false }).fg,
      normal_bg,
      0.1
    ).hex,
  })
  utils.hl.set(0, 'RenderMarkdownH6Bg', {
    bg = utils.hl.cblend(
      utils.hl.get(0, { name = 'RenderMarkdownH6', link = false }).fg,
      normal_bg,
      0.1
    ).hex,
  })
end

set_default_hlgroups()
vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('RenderMarkdownSetDefaultHlGroups', {}),
  desc = 'Set default highlight groups for render-markdown.nvim.',
  callback = set_default_hlgroups,
})
