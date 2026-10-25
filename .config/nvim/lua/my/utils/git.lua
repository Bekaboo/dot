---@class my.utils.git
local M = {}

vim.api.nvim_create_autocmd({ 'BufWrite', 'FileChangedShellPost' }, {
  group = vim.api.nvim_create_augroup('my.git.refresh_writetick', {}),
  callback = function(args)
    vim.b[args.buf].git_writetick = vim.uv.hrtime()
  end,
})

---@class my.git.diffstat
---@field add? integer
---@field removed? integer
---@field changed? integer

---Get the diff stats for the current buffer asynchronously
---@param buf integer? buffer handler, defaults to the current buffer
---@param args string[]? arguments passed to `git` command
---@return my.git.diffstat? # diff stats
function M.diffstat(buf, args)
  buf = vim._resolve_bufnr(buf or 0)
  if not vim.api.nvim_buf_is_valid(buf) then
    return {}
  end

  if vim.b[buf].git_diffstat_pending then
    return vim.b[buf].git_diffstat
  end

  if
    (vim.b[buf].git_diffstat_writetick or 0) < (vim.b[buf].git_writetick or 1)
  then
    local bufname = vim.api.nvim_buf_get_name(buf)
    local dirname = vim.fs.dirname(bufname)
    local now = vim.uv.hrtime()
    vim.b[buf].git_diffstat_pending = true
    local ok = pcall(
      vim.system,
      vim.list_extend({ 'git', '-C', dirname, unpack(args or {}) }, {
        '--no-pager',
        'diff',
        '-U0',
        '--no-color',
        '--no-ext-diff',
        '--',
        bufname,
      }),
      { stderr = false },
      vim.schedule_wrap(function(o)
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        vim.b[buf].git_diffstat_pending = nil

        local stat = { added = 0, removed = 0, changed = 0 }
        for _, line in ipairs(vim.split(o.stdout, '\n')) do
          if line:find('^@@ ') then
            local num_lines_old, num_lines_new =
              line:match('^@@ %-%d+,?(%d*) %+%d+,?(%d*)')
            num_lines_old = tonumber(num_lines_old) or 1
            num_lines_new = tonumber(num_lines_new) or 1
            local num_lines_changed = math.min(num_lines_old, num_lines_new)
            stat.changed = stat.changed + num_lines_changed
            if num_lines_old > num_lines_new then
              stat.removed = stat.removed + num_lines_old - num_lines_changed
            else
              stat.added = stat.added + num_lines_new - num_lines_changed
            end
          end
        end

        if (vim.b[buf].git_diffstat_writetick or 0) < now then
          vim.b[buf].git_diffstat = o.code == 0 and stat or nil
          vim.b[buf].git_diffstat_writetick = now
        end
      end)
    )
    if not ok then
      vim.b[buf].git_diffstat_pending = nil
    end
  end

  return vim.b[buf].git_diffstat
end

---Asynchronously execute git command and get output
---NOTE: output can be out of date
---@param buf integer? buffer handler, defaults to the current buffer
---@param args string[] arguments passed to `git` command
---@return string?
function M.execute(buf, args)
  buf = vim._resolve_bufnr(buf or 0)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local cache_key = vim.fn.sha256(table.concat(args)):sub(1, 8)
  local cache_key_writetick = cache_key .. '_writetick'
  local cache_key_pending = cache_key .. '_pending'

  -- Several statusline components request the same context on each redraw.
  -- Reuse the cached value until the outstanding request finishes.
  if vim.b[buf][cache_key_pending] then
    return vim.b[buf][cache_key]
  end

  if
    (vim.b[buf][cache_key_writetick] or 0) < (vim.b[buf].git_writetick or 1)
  then
    local now = vim.uv.hrtime()
    vim.b[buf][cache_key_pending] = true
    local ok = pcall(
      vim.system,
      {
        'git',
        '-C',
        vim.fs.dirname(vim.api.nvim_buf_get_name(buf)),
        unpack(args),
      },
      { stderr = false },
      vim.schedule_wrap(function(o)
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        vim.b[buf][cache_key_pending] = nil

        if (vim.b[buf][cache_key_writetick] or 0) < now then
          vim.b[buf][cache_key] = o.code == 0 and vim.trim(o.stdout) or nil
          vim.b[buf][cache_key_writetick] = now
        end
      end)
    )
    if not ok then
      vim.b[buf][cache_key_pending] = nil
    end
  end

  return vim.b[buf][cache_key]
end

---Get buffer's current work tree and git dir with fallback
---@param buf integer? buffer handler, default to current buffer
---@param fallback_args string[][] alternative git arguments to try
---@return string? work_tree
---@return string? git_dir
function M.resolve_context(buf, fallback_args)
  buf = vim._resolve_bufnr(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local command = { 'rev-parse', '--show-toplevel', '--absolute-git-dir' }
  local context = M.execute(buf, command)
  for _, args in ipairs(fallback_args) do
    if context then
      break
    end
    context = M.execute(buf, vim.list_extend(vim.deepcopy(args), command))
  end

  if not context then
    return
  end

  return context:match('^(.-)\n(.+)$')
end

return M
