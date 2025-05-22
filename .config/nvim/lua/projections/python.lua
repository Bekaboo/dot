return {
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
