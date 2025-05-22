-- Keymaps
vim.keymap.set('n', '<C-_>', '<Cmd>A<CR>', { desc = 'Edit alternate file' })

-- Extra transformers
vim.cmd([=[
  if !exists('g:projectionist_transformations')
    let g:projectionist_transformations = {}
  endif

  " Remove first slash separated component
  function! g:projectionist_transformations.tail(input, o) abort
    return substitute(a:input, '\(\/\)*[^/]\+\/*', '\1', '')
  endfunction

  " Remove all but first slash separated component
  function! g:projectionist_transformations.head(input, o) abort
    return matchstr(a:input, '\(\/\)*[^/]\+', '\1', '')
  endfunction
]=])

---Load projections for given filetype
---@param ft? string filetype to load, default to current buffer's filetype
---@return boolean new projection rules loaded
local function load_projections(ft)
  ft = ft or vim.bo.ft

  local projections_file = 'projections.' .. ft
  if package.loaded[projections_file] then
    return false
  end

  local has_projections, projections = pcall(require, projections_file)
  if not has_projections then
    return false
  end

  vim.g.projectionist_heuristics = vim.tbl_deep_extend(
    'force',
    vim.g.projectionist_heuristics or {},
    projections
  )
  return true
end

for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  load_projections(vim.bo[buf].ft)
end

vim.api.nvim_create_autocmd('FileType', {
  desc = 'Load projections lazily.',
  group = vim.api.nvim_create_augroup('LoadProjections', {}),
  callback = function(info)
    local ft = info.match
    if load_projections(ft) then
      vim.api.nvim_exec_autocmds('FileType', { pattern = ft })
    end
  end,
})
