local M = {}

---Get cmd to watch for AI comments
---@param file string
---@return string[]?
function M.watch_cmd(file)
  if not vim.uv.fs_stat(file) then
    return
  end

  local watch_cmds = require('plugin.aider.configs').opts.watch.cmds
  for _, cmd in ipairs(watch_cmds) do
    if vim.fn.executable(cmd[1]) == 1 then
      return vim
        .iter(cmd)
        :map(function(arg)
          return string.format(arg, file)
        end)
        :totable()
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
  local chat, is_new = require('plugin.aider.chat'):get(file)
  if not chat then
    return
  end

  -- Open chat panel, switch to it only if there is pending confirm
  chat:open(false)
  chat:on_update(function()
    if not chat:confirm_pending() and not chat:input_pending() then
      return
    end

    if chat:confirm_pending() then
      chat:open()
      vim.cmd.startinsert()
    end
    return true
  end)

  -- Update last change time of `file` to notify aider
  -- Do this only once for each aider instance because it will automatically
  -- watch for file changes once started
  if is_new then
    chat:on_update(function()
      if not chat:input_pending() then
        return
      end

      chat:wait_watcher(function()
        vim.uv.fs_stat(file, function(_, stat)
          if not stat then
            return
          end
          vim.uv.fs_utime(file, stat.atime.sec, stat.mtime.sec)
          -- Prevent file change errors on write by forcing nvim to recheck
          chat:sync_files(file)
        end)
      end)

      return true
    end)
  end
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
    callback = function(args)
      M.check(args.file)
    end,
  })
end

return M
