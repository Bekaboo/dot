-- Example structure:
-- Source: lua/<mod>/*.lua
-- Tests:  tests/<mod>/*.lua
--         tests/*.lua
return {
  ['lua/*.lua|tests/*_spec.lua'] = {
    ['lua/*.lua'] = {
      alternate = {
        'tests/{}_spec.lua',
        'tests/{dirname|tail}/{basename}_spec.lua',
      },
      type = 'source',
    },
    ['tests/*_spec.lua'] = {
      alternate = {
        -- Guess lua module name from project directory name,
        -- not always correct
        'lua/{project|basename|root}/{}.lua',
        'lua/{}.lua',
      },
      type = 'test',
    },
  },
}

