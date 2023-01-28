-- TODO: Support substitutions
-- TODO: add option to ask for confirmation before applying skeleton
-- TODO: match multiple skeletons
local M = {}

---@param user_config skeleton_config_t
function M.setup(user_config)
  local config = require('plugin.skeleton.config')
  config.config = vim.tbl_deep_extend('force', config.config, user_config or {})

  vim.api.nvim_create_autocmd({
    'BufNewFile',
    'BufRead',
  }, {
    pattern = '*',
    callback = function(...)
      require('plugin.skeleton.utils').apply_skeleton(...)
    end
  })
end

return M
