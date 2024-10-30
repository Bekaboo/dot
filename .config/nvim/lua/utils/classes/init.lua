return setmetatable({}, {
  __index = function(_, key)
    return require('utils.classes.' .. key)
  end,
})
