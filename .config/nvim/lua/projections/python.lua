return {
  ['Pipfile|pyproject.toml|requirements.txt|setup.cfg|setup.py|tox.ini|*.py'] = {
    ['*.py'] = {
      alternate = {
        '{dirname}/test_{basename}.py', -- test file in the same dir
        'tests/{dirname}/test_{basename}.py', -- test file in `tests` subdir
        -- Test file in parallel `test` dir, e.g.
        -- Source: <proj_name>/<mod>/<submod>/*.py
        -- Tests:  tests/<mod>/<submod>/test_*.py
        'tests/{dirname|tail}/test_{basename}.py',
        -- Test file for module, e.g.
        -- Source: <mod>/<submod>/*.py
        -- Tests:  <mod>/test_<submod>.py
        --         tests/<mod>/test_<submod>.py
        -- In this case we cannot switch back to the source because
        -- one test file corresponds to multiple source files
        '{dirname|dirname}/test_{dirname|basename}.py',
        '{dirname|tail|dirname}/test_{dirname|basename}.py',
        'tests/{dirname|dirname}/test_{dirname|basename}.py',
        'tests/{dirname|tail|dirname}/test_{dirname|basename}.py',
      },
      type = 'source',
    },
    ['**/test_*.py'] = {
      alternate = {
        '{}.py', -- source file in the same dir
        '{}', -- test is a module test
      },
      type = 'test',
    },
    ['tests/**/test_*.py'] = {
      alternate = {
        '{}.py', -- source file in parent dir
        '{}',
        -- Source file in parallel dir
        -- Guess source file containing dir (project dir)
        -- using base of project fullpath, not always correct.
        -- Required struct:
        -- Source: [PROJECT]/<proj_name>/<mod>/<submod>/*.py
        -- Tests:  [PROJECT]/tests/<mod>/<submod>/test_*.py
        -- where [PROJECT] ends with <proj_name>
        '{project|basename}/{}.py',
        '{project|basename}/{}',
      },
      type = 'test',
    },
  },
}
