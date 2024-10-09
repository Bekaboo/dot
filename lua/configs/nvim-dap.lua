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

local w_set_cond_breakpoint = wrap(set_cond_breakpoint)
local w_set_logpoint = wrap(set_logpoint)
local w_up = wrap(dap.up)
local w_down = wrap(dap.down)
local w_continue = wrap(dap.continue)
local w_pause = wrap(dap.pause)
local w_repl_open = wrap(dap.repl.open)
local w_toggle_breakpoint = wrap(dap.toggle_breakpoint)
local w_step_over = wrap(dap.step_over)
local w_step_into = wrap(dap.step_into)
local w_step_out = wrap(dap.step_out)
local w_terminate = wrap(dap.terminate)
local w_restart = wrap(dap.restart)

vim.keymap.set('n', '<F1>', w_up)
vim.keymap.set('n', '<F2>', w_down)
vim.keymap.set('n', '<F5>', w_continue)
vim.keymap.set('n', '<F6>', w_pause)
vim.keymap.set('n', '<F8>', w_repl_open)
vim.keymap.set('n', '<F9>', w_toggle_breakpoint)
vim.keymap.set('n', '<F10>', w_step_over)
vim.keymap.set('n', '<F11>', w_step_into)
vim.keymap.set('n', '<F17>', w_terminate)
vim.keymap.set('n', '<F23>', w_step_out)
vim.keymap.set('n', '<F41>', w_restart)
vim.keymap.set('n', '<F21>', w_set_cond_breakpoint) -- <S-F9>
vim.keymap.set('n', '<F45>', w_set_logpoint) -- <C-S-F9>

vim.keymap.set('n', '<Leader>Gk', w_up)
vim.keymap.set('n', '<Leader>Gj', w_down)
vim.keymap.set('n', '<Leader>G<Up>', w_up)
vim.keymap.set('n', '<Leader>G<Down>', w_down)
vim.keymap.set('n', '<Leader>Gc', w_continue)
vim.keymap.set('n', '<Leader>Gh', w_pause)
vim.keymap.set('n', '<Leader>Gp', w_pause)
vim.keymap.set('n', '<C-c>', w_pause)
vim.keymap.set('n', '<Leader>Ge', w_repl_open)
vim.keymap.set('n', '<Leader>Gb', w_toggle_breakpoint)
vim.keymap.set('n', '<Leader>Gn', w_step_over)
vim.keymap.set('n', '<Leader>Gi', w_step_into)
vim.keymap.set('n', '<Leader>Go', w_step_out)
vim.keymap.set('n', '<Leader>Gt', w_terminate)
vim.keymap.set('n', '<Leader>Gr', w_restart)
vim.keymap.set('n', '<Leader>GB', w_set_cond_breakpoint)
vim.keymap.set('n', '<Leader>Gl', w_set_logpoint)

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
vim.fn.sign_define('DapBreakpoint',          { text = vim.trim(icons.ui.DotLarge), texthl = 'DiagnosticSignHint' })
vim.fn.sign_define('DapBreakpointCondition', { text = vim.trim(icons.ui.Diamond), texthl = 'DiagnosticSignInfo' })
vim.fn.sign_define('DapBreakpointRejected',  { text = vim.trim(icons.ui.DotLarge), texthl = 'DiagnosticSignWarn' })
vim.fn.sign_define('DapLogPoint',            { text = vim.trim(icons.ui.Log), texthl = 'DiagnosticSignOk' })
vim.fn.sign_define('DapStopped',             { text = vim.trim(icons.ui.ArrowRight), texthl = 'DiagnosticSignError' })
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
