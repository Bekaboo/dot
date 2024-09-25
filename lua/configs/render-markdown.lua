local utils = require('utils')
local icons = utils.static.icons

require('render-markdown').setup({
  render_modes = true,
  signs = { enabled = false },
  bullet = {
    icons = { icons.Dot },
    right_pad = 0,
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
      utils.hl.get(0, { name = 'Normal', link = false }).bg,
      0.1
    ).hex,
  })

  local float_bg = utils.hl.get(0, { name = 'NormalFloat', link = false }).bg
  utils.hl.set(0, 'RenderMarkdownCodeFloat', {
    bg = utils.hl.cblend(
      utils.hl.cseperate(
        utils.hl.get(0, { name = 'Normal', link = false }).bg,
        utils.hl.get(0, { name = 'RenderMarkdownCode', link = false }).bg,
        0.9
      ).rgb,
      float_bg,
      0.1
    ).hex,
  })
  utils.hl.set(
    0,
    'RenderMarkdownCodeInlineFloat',
    { link = 'RenderMarkdownCodeFloat' }
  )
  utils.hl.set(0, 'RenderMarkdownH1BgFloat', {
    bg = utils.hl.cblend(
      utils.hl.get(0, { name = 'RenderMarkdownH1', link = false }).fg,
      float_bg,
      0.1
    ).hex,
  })
  utils.hl.set(0, 'RenderMarkdownH2BgFloat', {
    bg = utils.hl.cblend(
      utils.hl.get(0, { name = 'RenderMarkdownH2', link = false }).fg,
      float_bg,
      0.1
    ).hex,
  })
  utils.hl.set(0, 'RenderMarkdownH3BgFloat', {
    bg = utils.hl.cblend(
      utils.hl.get(0, { name = 'RenderMarkdownH3', link = false }).fg,
      float_bg,
      0.1
    ).hex,
  })
  utils.hl.set(0, 'RenderMarkdownH4BgFloat', {
    bg = utils.hl.cblend(
      utils.hl.get(0, { name = 'RenderMarkdownH4', link = false }).fg,
      float_bg,
      0.1
    ).hex,
  })
  utils.hl.set(0, 'RenderMarkdownH5BgFloat', {
    bg = utils.hl.cblend(
      utils.hl.get(0, { name = 'RenderMarkdownH5', link = false }).fg,
      float_bg,
      0.1
    ).hex,
  })
  utils.hl.set(0, 'RenderMarkdownH6BgFloat', {
    bg = utils.hl.cblend(
      utils.hl.get(0, { name = 'RenderMarkdownH6', link = false }).fg,
      float_bg,
      0.1
    ).hex,
  })
end

set_default_hlgroups()

local gid = vim.api.nvim_create_augroup('RenderMarkdownSetDefaultHlGroups', {})

vim.api.nvim_create_autocmd('ColorScheme', {
  desc = 'Set default highlight groups for render-markdown.nvim.',
  group = gid,
  callback = set_default_hlgroups,
})

vim.api.nvim_create_autocmd('FileType', {
  desc = 'Set background highlight groups for render-markdown in floating windows.',
  group = gid,
  pattern = { 'markdown', 'qml', 'org', 'norg' },
  -- Use `vim.schedule_wrap()` to wait for the LSP floating widow to open
  callback = vim.schedule_wrap(function(info)
    if not vim.api.nvim_buf_is_valid(info.buf) then
      return
    end

    for _, win in ipairs(vim.fn.win_findbuf(info.buf)) do
      if vim.fn.win_gettype(win) ~= 'popup' then
        goto continue
      end

      vim.api.nvim_win_call(win, function()
        vim.opt_local.winhl:append({
          RenderMarkdownCode = 'RenderMarkdownCodeFloat',
          RenderMarkdownCodeInline = 'RenderMarkdownCodeInlineFloat',
          RenderMarkdownH1Bg = 'RenderMarkdownH1BgFloat',
          RenderMarkdownH2Bg = 'RenderMarkdownH2BgFloat',
          RenderMarkdownH3Bg = 'RenderMarkdownH3BgFloat',
          RenderMarkdownH4Bg = 'RenderMarkdownH4BgFloat',
          RenderMarkdownH5Bg = 'RenderMarkdownH5BgFloat',
          RenderMarkdownH6Bg = 'RenderMarkdownH6BgFloat',
        })
      end)
      ::continue::
    end
  end),
})
