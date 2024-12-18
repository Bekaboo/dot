vim.g.codeium_filetypes = {
  text = false,
  markdown = false,
}

---Setup codeium keymaps to accept/iterate/dismiss completions
---@return nil
local function setup_keymaps()
  ---@param key string
  ---@param codeium_method string
  ---@param opts vim.keymap.set.Opts?
  ---@return nil
  local function amend(key, codeium_method, opts)
    require('utils.keymap').amend(
      'i',
      key,
      function(fallback)
        local result = vim.fn['codeium#' .. codeium_method]()
        return result ~= '' and result ~= '\t' and result or fallback()
      end,
      vim.tbl_deep_extend('force', {
        expr = true,
        silent = true,
      }, opts or {})
    )
  end

  vim.defer_fn(function()
    -- Same as fish shell keymaps
    amend('<C-f>', 'Accept', { desc = 'Accept suggestion' })
    amend('<Right>', 'Accept', { desc = 'Accept suggestion' })
    amend('<M-f>', 'AcceptNextWord', { desc = 'Accept next word' })
    amend('<M-Right>', 'AcceptNextWord', { desc = 'Accept next word' })
  end, 100)
end

---Launch codeium and start completion
---@return nil
local function launch_complete()
  if not vim.fn['codeium#Enabled']() then
    return
  end
  vim.fn['codeium#command#StartLanguageServer']()
  vim.fn['codeium#DebouncedComplete']()
end

-- Defer setup codeium because `vim.fn.mode()` returns 'n' if codeium is loaded
-- on InsertEnter (just BEFORE entering insert mode)
vim.schedule(function()
  if vim.startswith(vim.fn.mode(), 'i') then
    setup_keymaps()
    launch_complete()
    return
  end

  vim.api.nvim_create_autocmd('InsertEnter', {
    desc = 'Setup keymap <C-f> to accept suggestions from codeium.',
    once = true,
    callback = function()
      setup_keymaps()
      launch_complete()
      return true
    end,
  })
end)

vim.api.nvim_create_autocmd('InsertEnter', {
  desc = 'Disable codeium in big files.',
  group = vim.api.nvim_create_augroup('CodeiumSetup', {}),
  callback = function()
    if vim.b.bigfile then
      vim.b.codeium_enabled = false
      vim.b.codeium_excluded = true
    end
  end,
})
