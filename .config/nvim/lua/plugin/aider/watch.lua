local M = {}

local utils = require('plugin.aider.utils')
local configs = require('plugin.aider.configs')

---Get cmd to watch for AI comments
---@param file string
---@return string[]?
function M.watch_cmd(file)
  if not vim.uv.fs_stat(file) then
    return
  end

  local watch_cmds = configs.opts.watch.cmds
  for _, cmd in ipairs(watch_cmds) do
    local exe = cmd[1] and utils.os.exepath[cmd[1]] -- normalized grep tool execution path
    if exe then
      local result = vim.deepcopy(cmd)
      result[1] = exe
      for i, arg in ipairs(result) do
        result[i] = string.format(arg, file)
      end
      return result
    end
  end

  -- No watch cmd available
  vim.schedule(function()
    vim.notify_once(
      string.format(
        '[aider] cannot watch files, install one of: %s',
        table.concat(
          vim
            .iter(watch_cmds)
            :map(function(cmd)
              return string.format('`%s`', vim.fs.basename(cmd[1]))
            end)
            :totable(),
          ' '
        )
      ),
      vim.log.levels.WARN
    )
  end)
end

---Launch aider panel for `file` and properly update its change time so that
---aider can see it
---@param file string
function M.act(file)
  local chat = require('plugin.aider.chat').get(file)
  if not chat then
    return
  end

  -- Open chat panel, switch to it only if there is pending confirm
  chat:open(false)
  chat:on(function()
    return chat:confirm_pending() or chat:input_pending()
  end, function()
    if chat:confirm_pending() then
      chat:open()
      vim.cmd.startinsert()
    end
    return true
  end)

  -- Update last change time of `file` when aider is ready for input
  chat:on(chat.input_pending, function()
    chat:wait_watcher(function()
      vim.uv.fs_stat(file, function(_, stat)
        if stat then
          vim.uv.fs_utime(file, stat.atime.sec, stat.mtime.sec)
        end
      end)
    end)
    return true
  end)
end

---Check inline AI comments in given `file`
---@param file string
function M.check(file)
  vim.uv.fs_stat(file, function(_, stat)
    if not stat then
      return
    end

    local watch_cmd = M.watch_cmd(file)
    if not watch_cmd then
      return
    end

    vim.system(watch_cmd, {}, function(out)
      if out.code ~= 0 then
        return -- no AI comment found
      end
      vim.schedule(function()
        M.act(file)
      end)
    end)
  end)
end

---Start watching for inline AI comments
function M.watch()
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = vim.api.nvim_create_augroup('AiderWatch', {}),
    desc = 'Watch for AI comments.',
    callback = function(info)
      M.check(info.file)
    end,
  })
end

return M
