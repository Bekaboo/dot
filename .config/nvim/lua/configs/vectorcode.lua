---@param buf integer
local function vc_activate(buf)
  if vim.fn.executable('vectorcode') == 0 then
    vim.notify_once(
      '[vectorcode] `vectorcode` cli is missing, you can install it using `pipx install vectorcode`',
      vim.log.levels.WARN
    )
    return
  end

  -- Scan (vectorise) current project
  -- `vim.b._root_dir` is cached root dir of corresponding buffer,
  -- see `AutoCwd` augroup in `lua/core/autocmds.lua`
  local cwd = (function()
    local root_dir = vim.b[buf]._root_dir
    if root_dir and vim.fn.isdirectory(root_dir) == 1 then
      return root_dir
    end
    return vim.fs.root(buf, require('utils.fs').root_markers)
  end)()
  if vim.fn.isdirectory(vim.fs.joinpath(cwd, '.vectorcode')) == 0 then
    vim.system({ 'vectorcode', 'vectorise' }, { cwd = cwd })
  end

  local cacher = require('vectorcode.config').get_cacher_backend()
  cacher.async_check('config', function()
    ---@diagnostic disable-next-line: missing-fields
    cacher.register_buffer(buf, { n_query = 8 })
  end)
end

for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if #vim.lsp.get_clients({ bufnr = buf }) > 0 then
    vc_activate(buf)
  end
end

vim.api.nvim_create_autocmd('LspAttach', {
  desc = 'Automatically register LSP-enabled buffers for VectorCode',
  group = vim.api.nvim_create_augroup('VectorCodeAutoRegister', {}),
  callback = function(info)
    vc_activate(info.buf)
  end,
})
