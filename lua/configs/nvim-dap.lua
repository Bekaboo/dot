local dap = require('dap')
local static = require('utils.static')

local function set_cond_breakpoint()
  dap.set_breakpoint(nil, nil, vim.fn.input('Breakpoint condition: '))
end

local function set_logpoint()
  dap.set_breakpoint(nil, nil, nil, vim.fn.input('Log point message: '))
end

vim.keymap.set('n', '<F1>', dap.up, { noremap = true })
vim.keymap.set('n', '<F2>', dap.down, { noremap = true })
vim.keymap.set('n', '<F5>', dap.continue, { noremap = true })
vim.keymap.set('n', '<F6>', dap.pause, { noremap = true })
vim.keymap.set('n', '<F8>', dap.repl.open, { noremap = true })
vim.keymap.set('n', '<F9>', dap.toggle_breakpoint, { noremap = true })
vim.keymap.set('n', '<F10>', dap.step_over, { noremap = true })
vim.keymap.set('n', '<F11>', dap.step_into, { noremap = true })
vim.keymap.set('n', '<F17>', dap.terminate, { noremap = true })
vim.keymap.set('n', '<F23>', dap.step_out, { noremap = true })
vim.keymap.set('n', '<F41>', dap.restart, { noremap = true })
vim.keymap.set('n', '<F21>', set_cond_breakpoint, { noremap = true }) -- <S-F9>
vim.keymap.set('n', '<F45>', set_logpoint, { noremap = true }) -- <C-S-F9>

vim.keymap.set('n', '<Leader>Gk', dap.up, { noremap = true })
vim.keymap.set('n', '<Leader>Gj', dap.down, { noremap = true })
vim.keymap.set('n', '<Leader>G<Up>', dap.up, { noremap = true })
vim.keymap.set('n', '<Leader>G<Down>', dap.down, { noremap = true })
vim.keymap.set('n', '<Leader>Gc', dap.continue, { noremap = true })
vim.keymap.set('n', '<Leader>Gh', dap.pause, { noremap = true })
vim.keymap.set('n', '<Leader>Gp', dap.pause, { noremap = true })
vim.keymap.set('n', '<C-c>', dap.pause, { noremap = true })
vim.keymap.set('n', '<Leader>Ge', dap.repl.open, { noremap = true })
vim.keymap.set('n', '<Leader>Gb', dap.toggle_breakpoint, { noremap = true })
vim.keymap.set('n', '<Leader>Gn', dap.step_over, { noremap = true })
vim.keymap.set('n', '<Leader>Gi', dap.step_into, { noremap = true })
vim.keymap.set('n', '<Leader>Go', dap.step_out, { noremap = true })
vim.keymap.set('n', '<Leader>Gt', dap.terminate, { noremap = true })
vim.keymap.set('n', '<Leader>Gr', dap.restart, { noremap = true })
vim.keymap.set('n', '<Leader>GB', set_cond_breakpoint, { noremap = true })
vim.keymap.set('n', '<Leader>Gl', set_logpoint, { noremap = true })

vim.api.nvim_create_user_command('DapClear', dap.clear_breakpoints, {
  desc = 'Clear all breakpoints',
})

-- stylua: ignore start
vim.fn.sign_define('DapBreakpoint',          { text = vim.trim(static.icons.DotLarge), texthl = 'DiagnosticSignHint' })
vim.fn.sign_define('DapBreakpointCondition', { text = vim.trim(static.icons.Diamond), texthl = 'DiagnosticSignInfo' })
vim.fn.sign_define('DapBreakpointRejected',  { text = vim.trim(static.icons.DotLarge), texthl = 'DiagnosticSignWarn' })
vim.fn.sign_define('DapLogPoint',            { text = vim.trim(static.icons.Log), texthl = 'DiagnosticSignOk' })
vim.fn.sign_define('DapStopped',             { text = vim.trim(static.icons.ArrowRight), texthl = 'DiagnosticSignError' })
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
