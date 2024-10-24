local fs = require('utils.fs')

---Convert a `.ipynb` notebook buffer into a proper markdown buffer
---@param buf integer?
---@return nil
local function jupytext_convert(buf)
  buf = buf ~= 0 and buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local fpath_ipynb = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
  local fpath_cache = vim.fn.stdpath('cache') --[[@as string]]
  local fpath_cache_jupytext = vim.fs.joinpath(fpath_cache, 'jupytext')

  -- If jupytext is not installed, load the original buffer
  if vim.fn.executable('jupytext') == 0 then
    vim.cmd.edit(vim.fn.fnameescape(fpath_ipynb))
    vim.cmd.filetype('detect')
    return
  end

  if
    not vim.uv.fs_stat(fpath_cache_jupytext)
    and not vim.uv.fs_mkdir(fpath_cache_jupytext, 511)
  then
    vim.notify(
      '[jupytext] cannot create cache dir ' .. fpath_cache_jupytext,
      vim.log.levels.ERROR
    )
    return
  end

  local fpath_out = vim.fs.joinpath(
    fpath_cache_jupytext,
    (vim.fn.fnamemodify(fpath_ipynb, ':r'):gsub('%%', '%%%%'):gsub('/', '%%'))
  )
  local fpath_md = fpath_out .. '.md'
  local fpath_sha = fpath_out .. '.sha256'

  -- Get current and previous sha256sum of the notebook file
  local sha_prev = fs.read_file(fpath_sha)
  local sha_current = vim.fn.executable('sha256sum') == 1
    and vim.trim(vim.system({ 'sha256sum', fpath_ipynb }):wait().stdout)

  -- Remove stale cache
  if not sha_prev or not sha_current or sha_prev ~= sha_current then
    vim.fn.delete(fpath_md)
  end

  ---Write sha256sum for the ipynb file
  ---@return nil
  local function _write_sha()
    if vim.fn.executable('sha256sum') == 0 or fs.is_empty(fpath_ipynb) then
      return
    end
    vim.system({ 'sha256sum', fpath_ipynb }, {}, function(obj)
      fs.write_file(fpath_sha, vim.trim(obj.stdout))
    end)
  end

  -- Convert ipynb file to markdown file using jupytext
  -- Don't convert if the notebook does not exist or is empty
  if not fs.is_empty(fpath_ipynb) and not vim.uv.fs_stat(fpath_md) then
    local obj = vim
      .system({
        'jupytext',
        '--to=md',
        '--format-options',
        'notebook_metadata_filter=-all',
        '--output',
        fpath_md,
        fpath_ipynb,
      })
      :wait()

    if obj.code == 0 then
      _write_sha()
    else
      vim.schedule(function()
        vim.notify(
          '[jupytext] error reading from notebook: ' .. obj.stderr,
          vim.log.levels.ERROR
        )
      end)
    end
  end

  -- Markdown file not found, load original notebook
  if not vim.uv.fs_stat(fpath_md) then
    vim.cmd.edit(vim.fn.fnameescape(fpath_ipynb))
    vim.cmd.filetype('detect')
    -- Three possible cases if the markdown file is missing:
    -- 1. the notebook does not exist (empty)
    -- 2. the notebook exists but is empty (empty)
    -- 3. the notebook is corrupted (not empty)
    --
    -- In case 1 & 2, we still want to set the current filetype to markdown
    -- and update the notebook on write using the FileWriteCmd/BufWriteCmd
    -- callback
    --
    -- In case 3, we want to load the underlying json and fix the corrupted
    -- notebook without setting the filetype and resiter the
    -- FileWriteCmd/BufWriteCmd callback
    if not fs.is_empty(fpath_ipynb) then
      return
    end
  else
    local undolevels
    -- Only set clear undo history on the first time loading the buffer
    -- This is to prevent losing undo history when nvim reloads the buffer
    -- from file when it detects the file has been changed outside of nvim,
    -- either by jupytext, another nvim session, or other code editors, see
    -- `:h autoread` and `:h timestamp`
    if vim.bo[buf].ft ~= 'markdown' then
      undolevels = vim.bo[buf].undolevels
      vim.bo[buf].undolevels = -1
    end
    vim.cmd.read({
      args = { vim.fn.fnameescape(fpath_md) },
      mods = { silent = true, keepalt = true },
    })
    vim.cmd.delete({
      reg = '_',
      range = { 1 },
      mods = { emsg_silent = true },
    })
    if undolevels then
      vim.bo[buf].undolevels = undolevels
    end
  end

  -- Setting 'buftype' to 'acwrite' to indicate that the buffer will always be
  -- written with BufWriteCmd, this also disable auto-reloading when the
  -- jupyter notebook is changed outside of nvim
  --
  -- If 'buftype' is not set, when we unfocus the current nvim session with
  -- unsaved changes in the notebook buffer, nvim saves the buffer automatically
  -- (see the autosave augroup in `lua/core/autocmds`), then write the changes
  -- to the notebook file asynchronously, resulting in a newer timestamp in the
  -- notebook file than the buffer; when we refocus the nvim session,
  -- nvim detects the newer timestamp in the notebook file and reloads the
  -- buffer from the notebook file, removing extmarks and other buffer-local
  -- settings -- which is not what we want, see `:h timestamp`, `:h autoread`
  --
  -- To avoid this we can either block until the write to the notebook is finished
  -- in BufWriteCmd/FileWriteCmd, or set 'buftype' to 'acwrite' to disable
  -- auto-reloading when the notebook file is changed outside of nvim
  vim.bo[buf].bt = 'acwrite'
  vim.bo[buf].ft = 'markdown'
  vim.api.nvim_create_autocmd({ 'BufWriteCmd', 'FileWriteCmd' }, {
    group = vim.api.nvim_create_augroup('JupyText' .. buf, {}),
    buffer = buf,
    callback = function(info)
      vim.bo[info.buf].mod = false
      vim.cmd.write({
        vim.fn.fnameescape(fpath_md),
        mods = {
          silent = true,
          keepalt = true,
        },
        bang = true,
      })
      vim.system({
        'jupytext',
        '--update',
        '--from=md',
        '--to=ipynb',
        '--output',
        fpath_ipynb,
        fpath_md,
      }, {}, function(obj)
        if obj.code == 0 then
          _write_sha()
          return
        end
        -- If error, the notebook is possibly non-existent or is empty or
        -- corrupted, try without `--update` to fix it
        vim.system(
          {
            'jupytext',
            '--from=md',
            '--to=ipynb',
            '--output',
            fpath_ipynb,
            fpath_md,
          },
          {},
          vim.schedule_wrap(function(obj2)
            if obj2.code == 0 then
              _write_sha()
              return
            end
            vim.notify(
              '[jupytext] error updating notebook: ' .. obj2.stderr,
              vim.log.levels.ERROR
            )
          end)
        )
      end)
    end,
  })
end

---@param buf integer?
local function setup(buf)
  buf = buf and buf ~= 0 and buf or vim.api.nvim_get_current_buf()
  if vim.g.loaded_jupytext ~= nil then
    return
  end
  vim.g.loaded_jupytext = true

  if vim.api.nvim_buf_get_name(buf):match('%.ipynb$') then
    jupytext_convert(buf)
  end

  vim.api.nvim_create_autocmd('BufReadCmd', {
    group = vim.api.nvim_create_augroup('JupyText', {}),
    pattern = '*.ipynb',
    callback = function(info)
      jupytext_convert(info.buf)
    end,
  })
end

return { setup = setup }
