local utils = require('utils')

return setmetatable({}, {
  __index = function(_, key)
    local has_local_util, local_util =
      pcall(require, 'plugin.winbar.utils.' .. key)
    if has_local_util then
      return local_util
    end
    return utils[key]
  end,
})
