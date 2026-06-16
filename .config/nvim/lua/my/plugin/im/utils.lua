local M = {}

---Check if we are in *input modes*.
---
---*Input modes* are modes where the input method should be activated,
---including insert mode, replace mode, terminal mode, select mode, and
---command mode when command type is '/', '?', '@', or '-'.
---Notice that command mode when command type is ':', '>', or '=' is not
---considered as input modes, because in these cases one will not want to
---insert CJK, even if the input method is activated in the current buffer.
---@return boolean
function M.inside_input_mode()
  local mode = vim.fn.mode()
  return (
    mode:find('^[itRss\x13]')
    or mode:find('^c') and vim.fn.getcmdtype():find('[/?@-]')
  )
      and true
    or false
end

return M
