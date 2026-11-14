---@diagnostic disable: lowercase-global
-- luacheck: ignore 111
std = 'luajit'
globals = { 'vim' }
max_line_length = false

files['tests'] = {
  globals = {
    'assert',
    'before_each',
    'after_each',
    'describe',
    'it',
    'pending',
  },
}
