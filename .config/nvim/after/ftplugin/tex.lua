-- In some tex projects, cwd is set to the parent dir of the project, making
-- the `$FILE_PATH` placeholder in the img-clip paste template include the
-- project dir, different from how latexmk sees the image path.
-- See:
-- - `lua/pack/specs/opt/img-clip.lua`
-- - `lua/core/autocmds.lua`
--
-- So we treat `main.tex` as a root marker to properly detect the root dir of
-- some tex projects.
vim.b.root_markers =
  vim.list_extend({ 'main.tex' }, require('utils.fs').root_markers)
