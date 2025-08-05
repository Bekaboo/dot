local icons = require('utils.static.icons')

require('dap-view').setup({
  auto_toggle = true,
  windows = {
    terminal = {
      start_hidden = true,
    },
  },
  winbar = {
    base_sections = {
      -- stylua: ignore start
      breakpoints = { short_label = 'Brk [B]' },
      scopes      = { short_label = 'Sco [S]' },
      exceptions  = { short_label = 'Exp [E]' },
      watches     = { short_label = 'Wat [W]' },
      threads     = { short_label = 'Thr [T]' },
      repl        = { short_label = 'Rep [R]' },
      console     = { short_label = 'Con [C]' },
      -- stylua: ignore end
    },
    controls = {
      icons = {
        -- stylua: ignore start
        disconnect = vim.trim(icons.debug.Disconnect),
        pause      = vim.trim(icons.debug.Pause),
        play       = vim.trim(icons.debug.Start),
        run_last   = vim.trim(icons.debug.Restart),
        step_back  = vim.trim(icons.debug.StepBack),
        step_into  = vim.trim(icons.debug.StepInto),
        step_out   = vim.trim(icons.debug.StepOut),
        step_over  = vim.trim(icons.debug.StepOver),
        terminate  = vim.trim(icons.debug.Stop),
        -- stylua: ignore end
      },
    },
  },
})
