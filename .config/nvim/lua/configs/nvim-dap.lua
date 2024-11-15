local dap = require('dap')
local keymap = require('utils.keymap')
local icons = require('utils.static.icons')

local function set_cond_breakpoint()
  dap.set_breakpoint(nil, vim.fn.input('Breakpoint condition: '))
end

local function set_logpoint()
  dap.set_breakpoint(nil, nil, vim.fn.input('Log point message: '))
end

local last_dap_fn = function() end

---Wrap a function to set it as the last function to be called
---@param fn function
---@return function
local function wrap(fn)
  return function()
    last_dap_fn = fn
    fn()
  end
end

local dap_set_cond_breakpoint = wrap(set_cond_breakpoint)
local dap_set_logpoint = wrap(set_logpoint)
local dap_up = wrap(dap.up)
local dap_down = wrap(dap.down)
local dap_continue = wrap(dap.continue)
local dap_pause = wrap(dap.pause)
local dap_repl_open = wrap(dap.repl.open)
local dap_toggle_breakpoint = wrap(dap.toggle_breakpoint)
local dap_step_over = wrap(dap.step_over)
local dap_step_into = wrap(dap.step_into)
local dap_step_out = wrap(dap.step_out)
local dap_terminate = wrap(dap.terminate)
local dap_restart = wrap(dap.restart)

vim.keymap.set('n', '<F1>', dap_up)
vim.keymap.set('n', '<F2>', dap_down)
vim.keymap.set('n', '<F5>', dap_continue)
vim.keymap.set('n', '<F6>', dap_pause)
vim.keymap.set('n', '<F8>', dap_repl_open)
vim.keymap.set('n', '<F9>', dap_toggle_breakpoint)
vim.keymap.set('n', '<F10>', dap_step_over)
vim.keymap.set('n', '<F11>', dap_step_into)
vim.keymap.set('n', '<F17>', dap_terminate)
vim.keymap.set('n', '<F23>', dap_step_out)
vim.keymap.set('n', '<F41>', dap_restart)
vim.keymap.set('n', '<F21>', dap_set_cond_breakpoint) -- <S-F9>
vim.keymap.set('n', '<F45>', dap_set_logpoint) -- <C-S-F9>

vim.keymap.set('n', '<Leader>Gk', dap_up)
vim.keymap.set('n', '<Leader>Gj', dap_down)
vim.keymap.set('n', '<Leader>G<Up>', dap_up)
vim.keymap.set('n', '<Leader>G<Down>', dap_down)
vim.keymap.set('n', '<Leader>Gc', dap_continue)
vim.keymap.set('n', '<Leader>Gh', dap_pause)
vim.keymap.set('n', '<Leader>Gp', dap_pause)
vim.keymap.set('n', '<C-c>', dap_pause)
vim.keymap.set('n', '<Leader>Ge', dap_repl_open)
vim.keymap.set('n', '<Leader>Gb', dap_toggle_breakpoint)
vim.keymap.set('n', '<Leader>Gn', dap_step_over)
vim.keymap.set('n', '<Leader>Gi', dap_step_into)
vim.keymap.set('n', '<Leader>Go', dap_step_out)
vim.keymap.set('n', '<Leader>Gt', dap_terminate)
vim.keymap.set('n', '<Leader>Gr', dap_restart)
vim.keymap.set('n', '<Leader>GB', dap_set_cond_breakpoint)
vim.keymap.set('n', '<Leader>Gl', dap_set_logpoint)
vim.keymap.set('n', '<Leader>G<Esc>', '<Nop>')

-- When there's active dap session, use `<CR>` to repeat the last dap function
keymap.amend('n', '<CR>', function(fallback)
  if dap.session() then
    last_dap_fn()
    return
  end
  fallback()
end)

vim.api.nvim_create_user_command('DapClear', dap.clear_breakpoints, {
  desc = 'Clear all breakpoints',
})

-- stylua: ignore start
vim.fn.sign_define('DapBreakpoint',          { text = vim.trim(icons.debug.Breakpoint), texthl = 'DiagnosticSignHint' })
vim.fn.sign_define('DapBreakpointCondition', { text = vim.trim(icons.debug.BreakpointCondition), texthl = 'DiagnosticSignInfo' })
vim.fn.sign_define('DapBreakpointRejected',  { text = vim.trim(icons.debug.BreakpointRejected), texthl = 'DiagnosticSignWarn' })
vim.fn.sign_define('DapLogPoint',            { text = vim.trim(icons.debug.BreakpointLog), texthl = 'DiagnosticSignOk' })
vim.fn.sign_define('DapStopped',             { text = vim.trim(icons.debug.StackFrame), texthl = 'DiagnosticSignError' })
-- stylua: ignore end

dap.adapters = {}
dap.configurations = {}

---Load debug adapter specs for given filetype
---@param ft string
local function load_spec(ft)
  if dap.configurations[ft] then
    return
  end

  local ok, spec = pcall(require, 'dap.' .. ft)
  if not ok then
    return
  end

  dap.adapters[spec.config[1].type] = spec.adapter
  dap.configurations[ft] = spec.config
end

for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  load_spec(vim.bo[buf].ft)
end

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('DapLoadSpecs', {}),
  callback = function(info)
    load_spec(info.match)
  end,
})
