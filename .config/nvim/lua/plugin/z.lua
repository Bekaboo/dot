local M = {}

---Change directory to the most frequently visited directory using `z`
---@param input string[]
function M.z(input)
  local dest =
    vim.trim(vim.fn.system('z -e ' .. table.concat(
      vim.tbl_map(function(path)
        return vim.fn.shellescape(vim.fn.expand(path))
      end, input),
      ' '
    )))
  if dest and (vim.uv.fs_stat(dest) or {}).type == 'directory' then
    vim.cmd.lcd(vim.fn.fnameescape(dest))
  end
end

---Complete `:Z` command
---@param input string?
---@return string[]
function M.cmp(input)
  local scored_paths =
    vim.fn.systemlist('z -l ' .. vim.fn.shellescape(input or ''))
  local paths = {}
  for _, candidate in ipairs(scored_paths) do
    local path = candidate:match('^[0-9.]+%s+(.*)') -- trim score
    if path then
      table.insert(paths, path)
    end
  end
  return paths
end

---Select and jump to z directories using `vim.ui.select()`
---@param input string?
function M.select(input)
  local paths = M.cmp(input)
  vim.ui.select(paths, {
    prompt = 'Change cwd to: ',
  }, function(choice)
    if not choice then
      return
    end
    vim.cmd.lcd({
      vim.fn.fnameescape(choice),
      mods = {
        silent = true,
        emsg_silent = true,
      },
    })
  end)
end

---Setup `:Z` command
function M.setup()
  vim.fn.system('z')
  if vim.v.shell_error ~= 0 then
    vim.notify_once('[z] `z` executable not found', vim.log.levels.WARN)
    return
  end

  if vim.g.loaded_z then
    return
  end
  vim.g.loaded_z = true

  vim.api.nvim_create_user_command('Z', function(args)
    M.z(args.fargs)
  end, {
    nargs = '*',
    desc = 'Change local working directory using z.',
    complete = M.cmp,
  })
  vim.api.nvim_create_user_command('ZSelect', function(args)
    M.select(args.args)
  end, {
    nargs = '*',
    desc = 'Change local working directory using z.',
    complete = M.cmp,
  })
end

return M
