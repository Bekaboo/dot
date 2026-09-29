return setmetatable({
  borders = nil, ---@module 'my.utils.static.borders'
  boxes = nil, ---@module 'my.utils.static.boxes'
  icons = nil, ---@module 'my.utils.static.icons'
}, {
  __index = function(_, key)
    return require('my.utils.static.' .. key)
  end,
})
