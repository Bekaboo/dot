-- Example structure:
-- Source: lua/<mod>/*.lua
-- Tests:  lua/<mod>/*_spec.lua
--         tests/<mod>/*.lua
--         tests/*.lua
return {
  ['lua/*.lua|tests/*_spec.lua'] = {
    ['lua/*.lua'] = {
      alternate = {
        'lua/{}_spec.lua',
        'tests/{dirname|basename}/{basename}_spec.lua',
        'tests/{basename}_spec.lua',
      },
      type = 'source',
    },
    ['lua/*_spec.lua'] = {
      alternate = 'lua/{}.lua',
      type = 'test',
    },
    ['tests/*_spec.lua'] = {
      alternate = {
        -- Guess lua module name from project directory name,
        -- not always correct
        'lua/{project|basename}/{}.lua',
        'lua/{}.lua',
      },
      type = 'test',
    },
  },
}

