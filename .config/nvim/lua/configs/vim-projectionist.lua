vim.keymap.set('n', '<C-_>', '<Cmd>A<CR>', { desc = 'Edit alternate file' })

-- Heuristic rules to detect alternate files
vim.g.projectionist_heuristics = {
  -- C/C++
  ['*.{c,cc,cpp,h,hh,hpp}'] = {
    ['*.c'] = {
      alternate = '{}.h',
      type = 'source',
    },
    ['*.cc'] = {
      alternate = {
        '{}.hh',
        '{}.h',
      },
      type = 'source',
    },
    ['*.cpp'] = {
      alternate = {
        '{}.hpp',
        '{}.h',
      },
      type = 'source',
    },
    ['*.h'] = {
      alternate = {
        '{}.cpp',
        '{}.cc',
        '{}.c',
      },
      type = 'header',
    },
    ['*.hh'] = {
      alternate = '{}.cc',
      type = 'header',
    },
    ['*.hpp'] = {
      alternate = '{}.cpp',
      type = 'header',
    },
  },

  -- Lua
  -- Example structure:
  -- Source: lua/<mod>/*.lua
  -- Tests:  lua/<mod>/*_spec.lua
  --         tests/<mod>/*.lua
  --         tests/*.lua
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

  -- Go
  ['*.go'] = {
    ['*.go'] = {
      alternate = '{}_test.go',
      type = 'source',
    },
    ['*_test.go'] = {
      alternate = '{}.go',
      type = 'test',
    },
  },

  -- Python (pytest)
  ['*.py'] = {
    ['*.py'] = {
      alternate = {
        'test_{basename}.py', -- test file in the same dir
        'tests/test_{basename}.py', -- test file in `test/` subdir
      },
      type = 'source',
    },
    ['**/*.py'] = {
      alternate = {
        '{dirname}/test_{basename}.py',
        'tests/{dirname}/test_{basename}.py',
      },
      type = 'source',
    },
    ['test_*.py'] = {
      alternate = '{}.py',
      type = 'test',
    },
    ['tests/test_*.py'] = {
      alternate = '{}.py',
      type = 'test',
    },
    ['tests/**/test_*.py'] = {
      alternate = '{dirname}/{basename}.py',
      type = 'test',
    },
  },
}
