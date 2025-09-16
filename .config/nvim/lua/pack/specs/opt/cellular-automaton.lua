return {
  src = 'https://github.com/Eandrju/cellular-automaton.nvim',
  data = {
    cmds = 'CellularAutomaton',
    -- Monkey-patch to fix window content shifting when the host window has
    -- winbar attached, see:
    -- https://github.com/Eandrju/cellular-automaton.nvim/pull/37
    postload = function()
      local ui = require('cellular-automaton.ui')
      local open_window = ui.open_window

      ---@param host_win integer
      ---@diagnostic disable-next-line: duplicate-set-field
      function ui.open_window(host_win, ...)
        local result = { open_window(host_win, ...) }
        local win = result[1] ---@type integer

        -- Adjust animation window according to offset caused by winbar
        local row_offset = vim.wo[host_win].winbar ~= '' and 1 or 0
        vim.api.nvim_win_set_config(
          win,
          vim.tbl_deep_extend('force', vim.api.nvim_win_get_config(win), {
            height = vim.api.nvim_win_get_height(host_win) - row_offset,
            row = vim.api.nvim_win_get_position(host_win)[1] + row_offset,
          })
        )

        return unpack(result)
      end
    end,
  },
}
