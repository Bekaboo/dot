if pcall(require, 'image') then
  vim.g.molten_image_provider = 'image.nvim'
end

vim.g.molten_auto_init_behavior = 'init'
vim.g.molten_enter_output_behavior = 'open_and_enter'
vim.g.molten_output_win_max_height = 16
vim.g.molten_output_win_cover_gutter = false
vim.g.molten_output_win_border = 'single'
vim.g.molten_output_win_style = 'minimal'
vim.g.molten_auto_open_output = false
vim.g.molten_output_show_more = true
vim.g.molten_virt_text_max_lines = 16
vim.g.molten_wrap_output = true

---Shows a warning message from molten
---@param msg string Content of the notification to show to the user.
---@param level integer|nil One of the values from |vim.log.levels|.
---@param opts table|nil Optional parameters. Unused by default.
---@return nil
local function molten_warn(msg, level, opts)
  vim.notify('[Molten] ' .. msg, level or vim.log.levels.WARN, opts)
end

local essentials = {
  pynvim = true,
  ipykernel = true,
  jupyter_client = true,
}

local deps = {
  cairosvg = true,
  ipykernel = true,
  jupyter_client = true,
  kaleido = true,
  nbformat = true,
  plotly = true,
  pnglatex = true,
  pynvim = true,
  pyperclip = true,
  pyqt6 = true,
};

---Check all dependencies, install them if they are missing
(function()
  if vim.fn.executable('pip') == 0 then
    molten_warn('pip not found, skipping python dependency check')
    return
  end

  molten_warn('checking python dependencies...', vim.log.levels.INFO)
  for pkg, _ in pairs(deps) do
    vim.system(
      { 'pip', 'show', pkg },
      {},
      vim.schedule_wrap(function(obj)
        if obj.code == 0 then
          deps[pkg] = nil
          return
        end

        molten_warn('dependency ' .. pkg .. ' not found', vim.log.levels.INFO)
        -- Install dependencies automatically only if we are in a virtual
        -- environment
        if not vim.env.VIRTUAL_ENV then
          return
        end

        vim.system(
          { 'pip', 'install', pkg },
          {},
          vim.schedule_wrap(function(o)
            if o.code == 0 then
              molten_warn('installed ' .. pkg, vim.log.levels.INFO)
            else
              molten_warn(
                string.format('failed to install %s: %s', pkg, o.stderr or '')
              )
            end
            deps[pkg] = nil
          end)
        )
      end)
    )
  end
end)()

-- Block until all dependencies have been checked
-- When in a virtual environment, we need to wait longer for the possible
-- installation of dependencies
local CHECK_DEPS_TIMEOUT = vim.env.VIRTUAL_ENV and 10000 or 4000
vim.wait(CHECK_DEPS_TIMEOUT, function()
  return vim.tbl_isempty(deps)
end)

if not vim.tbl_isempty(deps) then
  molten_warn(
    'missing dependencies: ' .. table.concat(vim.tbl_keys(deps), ', ')
  )

  local missing_essentials = vim.tbl_filter(function(pkg)
    return essentials[pkg]
  end, vim.tbl_keys(deps))
  if not vim.tbl_isempty(missing_essentials) then
    molten_warn(
      'missing essential dependencies: '
        .. table.concat(missing_essentials, ', ')
    )
    molten_warn('abort')
    return
  end
end

-- Molten is lazy-loaded, so we need to re-generate and source rplugin manifest
if not pcall(vim.fn.MoltenStatusLineInit) then
  vim.cmd.UpdateRemotePlugins()
  local manifest = vim.g.loaded_remote_plugins
  if manifest and (vim.uv.fs_stat(manifest) or {}).type == 'file' then
    vim.cmd.source(manifest)
  end
end

local groupid = vim.api.nvim_create_augroup('MoltenSetup', {})
vim.api.nvim_create_autocmd('BufEnter', {
  desc = 'Change the configuration when editing a python file.',
  pattern = '*.py',
  group = groupid,
  callback = function(info)
    if info.buf ~= vim.api.nvim_get_current_buf() then
      return
    end
    if require('molten.status').initialized() == 'Molten' then -- this is kinda a hack...
      vim.fn.MoltenUpdateOption('output_win_border', 'single')
      vim.fn.MoltenUpdateOption('virt_lines_off_by_1', nil)
      vim.fn.MoltenUpdateOption('virt_text_output', nil)
    else
      vim.g.molten_output_win_border = 'single'
      vim.g.molten_virt_lines_off_by_1 = nil
      vim.g.molten_virt_text_output = nil
    end
  end,
})

vim.api.nvim_create_autocmd('BufEnter', {
  desc = 'Undo config changes when we go back to a markdown or quarto file.',
  pattern = { '*.md', '*.ipynb' },
  group = groupid,
  callback = function(info)
    if info.buf ~= vim.api.nvim_get_current_buf() then
      return
    end
    if require('molten.status').initialized() == 'Molten' then
      vim.fn.MoltenUpdateOption('output_win_border', { '', '', '', '' })
      vim.fn.MoltenUpdateOption('virt_lines_off_by_1', true)
      vim.fn.MoltenUpdateOption('virt_text_output', true)
    else
      vim.g.molten_output_win_border = { '', '', '', '' }
      vim.g.molten_virt_lines_off_by_1 = true
      vim.g.molten_virt_text_output = true
    end
    -- Do not show molten cell background in markdown/quarto files
    vim.opt_local.winhl:append('MoltenCell:')
  end,
})

---Send code cell to molten
---@param cell code_cell_t
---@return nil
local function send(cell)
  local range = cell.range
  vim.fn.MoltenEvaluateRange(range.from[1] + 1, range.to[1])
end

---Code range, 0-based, end-exclusive
---@class code_range_t
---@field from integer[] 0-based (row, col) array
---@field to integer[] 0-based (row, col) array

---@class code_cell_t
---@field lang string?
---@field text table<string>
---@field range code_range_t

---Check if two ranges are overlapped
---@param r1 code_range_t
---@param r2 code_range_t
---@return boolean
local function is_overlapped(r1, r2)
  return r1.from[1] <= r2.to[1] and r2.from[1] <= r1.to[1]
end

---Get the overlap between two (line) ranges
---@param r1 code_range_t
---@param r2 code_range_t
---@return code_range_t?
local function get_overlap(r1, r2)
  if is_overlapped(r1, r2) then
    return {
      from = { math.max(r1.from[1], r2.from[1]), 0 },
      to = { math.min(r1.to[1], r2.to[1]), 0 },
    }
  end
end

---Extract code cells that overlap the given range,
---removes cells with a language that's in the ignore list
---@param lang string
---@param code_chunks table<string, code_cell_t>
---@param range code_range_t
---@param partial boolean?
---@return code_cell_t[]
local function extract_cells(lang, code_chunks, range, partial)
  if not code_chunks[lang] then
    return {}
  end

  local chunks = {}

  if partial then
    for _, chunk in ipairs(code_chunks[lang]) do
      local overlap = get_overlap(chunk.range, range)
      if overlap then
        if vim.deep_equal(overlap, chunk.range) then -- full overlap
          table.insert(chunks, chunk)
        else -- partial overlap
          local text = {}
          local lnum_start = overlap.from[1] - chunk.range.from[1] + 1
          local lnum_end = lnum_start + overlap.to[1] - overlap.from[1]
          for i = lnum_start, lnum_end do
            table.insert(text, chunk.text[i])
          end
          table.insert(
            chunks,
            vim.tbl_extend('force', chunk, {
              text = text,
              range = overlap,
            })
          )
        end
      end
    end
  else
    for _, chunk in ipairs(code_chunks[lang]) do
      if is_overlapped(chunk.range, range) then
        table.insert(chunks, chunk)
      end
    end
  end

  return chunks
end

local otk

---@type table<string, true>
local not_runnable = {
  markdown = true,
  markdown_inline = true,
  yaml = true,
}

---Find valid language under cursor that can be sent to REPL
---@return string?
local function get_valid_repl_lang()
  local lang = otk.get_current_language_context()
  if not lang or not_runnable[lang] then
    return
  end
  return lang
end

---Run code for the current language that overlap the given range
---
---Code are run in chunks (cells) , i.e. the whole chunk will be sent to
---REPL even when there are only partial overlap between the chunk and `range`
---@param range code_range_t a range, for with any overlapping code cells are run
---@return nil
local function run_cell(range)
  local buf = vim.api.nvim_get_current_buf()
  local lang = get_valid_repl_lang() or 'python'

  otk.sync_raft(buf)
  local otk_buf_info = otk.rafts[buf]
  if not otk_buf_info then
    molten_warn('code runner not initialized for buffer ' .. buf)
    return
  end

  local filtered = extract_cells(lang, otk_buf_info.code_chunks, range)
  if #filtered == 0 then
    molten_warn('no code found for ' .. lang)
    return
  end
  for _, chunk in ipairs(filtered) do
    send(chunk)
  end
end

---Run current cell
---@return nil
local function run_cell_current()
  local y = vim.api.nvim_win_get_cursor(0)[1]
  local r = { y, 0 }
  local range = { from = r, to = r }
  run_cell(range)
end

---Run current cell and all above
---@return nil
local function run_cell_above()
  local y = vim.api.nvim_win_get_cursor(0)[1]
  local range = { from = { 0, 0 }, to = { y, 0 } }
  run_cell(range)
end

---Run current cell and all below
---@return nil
local function run_cell_below()
  local y = vim.api.nvim_win_get_cursor(0)[1]
  local range = { from = { y, 0 }, to = { math.huge, 0 } }
  run_cell(range)
end

---Run current line of code
---@return nil
local function run_line()
  local lang = get_valid_repl_lang()
  if not lang then
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  local pos = vim.api.nvim_win_get_cursor(0)

  ---@type code_cell_t
  local cell = {
    lang = lang,
    range = { from = { pos[1] - 1, 0 }, to = { pos[1], 0 } },
    text = vim.api.nvim_buf_get_lines(buf, pos[1] - 1, pos[1], false),
  }

  send(cell)
end

---Run code in range `range`
---
---Code are run in lines, i.e. only code lines in `range` will be sent to REPL,
---if there is a partial overlap between `range` and a code chunk,
---only the lines inside `range` will be run
---@param range code_range_t
---@return nil
local function run_range(range)
  local buf = vim.api.nvim_get_current_buf()
  local lang = get_valid_repl_lang() or 'python'

  otk.sync_raft(buf)
  local otk_buf_info = otk.rafts[buf]
  if not otk_buf_info then
    molten_warn('code runner not initialized for buffer ' .. buf)
    return
  end

  local filtered = extract_cells(lang, otk_buf_info.code_chunks, range, true)
  if #filtered == 0 then
    molten_warn('no code found for ' .. lang)
    return
  end

  for _, chunk in ipairs(filtered) do
    send(chunk)
  end
end

---Run code in previous visual selection
---@return nil
local function run_visual()
  local vstart = vim.fn.getpos("'<")
  local vend = vim.fn.getpos("'>")
  run_range({
    from = { vstart[2] - 1, 0 },
    to = { vend[2], 0 },
  })
end

---Run code covered by operator
---@return nil
local function run_operator()
  vim.opt.opfunc = 'v:lua._molten_nb_run_opfunc'
  vim.api.nvim_feedkeys('g@', 'n', false)
end

---@param _ 'line'|'char'|'block' operator type, ignored
---@return nil
function _G._molten_nb_run_opfunc(_)
  local ostart = vim.fn.getpos("'[")
  local oend = vim.fn.getpos("']")
  run_range({
    from = { ostart[2] - 1, 0 },
    to = { oend[2], 0 },
  })
end

---Set buffer-local keymaps and commands
---@param buf integer? buffer handler, defaults to current buffer
---@return nil
local function setup_buf_keymaps_and_commands(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local ft = vim.bo[buf].ft
  if ft ~= 'markdown' and ft ~= 'python' then
    return
  end

  -- Skip non-notebook markdown files
  if
    ft == 'markdown'
    and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':e') ~= 'ipynb'
  then
    return
  end

  vim.keymap.set('n', '<C-c>', vim.cmd.MoltenInterrupt, {
    buffer = buf,
    desc = 'Interrupt kernel',
  })
  vim.keymap.set('n', '<C-j>', function()
    vim.cmd.MoltenEnterOutput({ mods = { noautocmd = true } })
    if vim.bo.ft ~= 'molten_output' then
      return
    end

    if vim.fn.exists('*matchup#loader#bufwinenter') == 1 then
      vim.fn['matchup#loader#bufwinenter']()
    end

    vim.keymap.set('n', '<C-k>', '<C-w>c', {
      buffer = true,
      desc = 'Exit cell output',
    })

    local src_win = vim.fn.win_getid(vim.fn.winnr('#'))
    local output_win = vim.api.nvim_get_current_win()
    vim.api.nvim_create_autocmd('WinScrolled', {
      desc = 'Close molten output win when src win is scrolled.',
      group = vim.api.nvim_create_augroup('MoltenCloseOutputWin' .. buf, {}),
      buffer = buf,
      callback = function(info)
        if src_win == tonumber(info.match) then
          vim.schedule(function()
            if vim.api.nvim_win_is_valid(output_win) then
              vim.api.nvim_win_close(output_win, false)
            end
          end)
        end
      end,
    })
  end, { buffer = buf, desc = 'Enter cell output' })

  local otk_ok
  otk_ok, otk = pcall(require, 'otter.keeper')
  -- Use otter to recognized codeblocks in markdown files,
  -- so we can run current codeblock directly without selection
  -- using `<CR>`, and other good stuffs
  -- stylua: ignore start
  if ft == 'markdown' and otk_ok then
    vim.api.nvim_buf_create_user_command(buf, 'MoltenNotebookRunLine', run_line, {})
    vim.api.nvim_buf_create_user_command(buf, 'MoltenNotebookRunCellAbove', run_cell_above, {})
    vim.api.nvim_buf_create_user_command(buf, 'MoltenNotebookRunCellBelow', run_cell_below, {})
    vim.api.nvim_buf_create_user_command(buf, 'MoltenNotebookRunCellCurrent', run_cell_current, {})
    vim.api.nvim_buf_create_user_command(buf, 'MoltenNotebookRunVisual', run_visual, { range = true })
    vim.api.nvim_buf_create_user_command(buf, 'MoltenNotebookRunOperator', run_operator, {})
    vim.keymap.set('n', '<LocalLeader><CR>', run_operator, { buffer = buf, desc = 'Run code selected by operator' })
    vim.keymap.set('n', '<LocalLeader>k', run_cell_above, { buffer = buf, desc = 'Run current cell and all above' })
    vim.keymap.set('n', '<LocalLeader>j', run_cell_below, { buffer = buf, desc = 'Run current cell and all below' })
    vim.keymap.set('n', '<CR>', run_cell_current, { buffer = buf, desc = 'Run current cell' })
    vim.keymap.set('x', '<CR>', ':<C-u>MoltenNotebookRunVisual<CR>', { buffer = buf, desc = 'Run selected code' })
  else -- ft == 'python' or otter.keeper not found
    vim.keymap.set('n', '<LocalLeader><CR>', vim.cmd.MoltenEvaluateOperator, { buffer = buf, desc = 'Run code selected by operator' })
    vim.keymap.set('n', '<LocalLeader><CR><CR>', vim.cmd.MoltenReevaluateAll, { buffer = buf, desc = 'Rerun all cells' })
    vim.keymap.set('n', '<CR>', '<Cmd>MoltenReevaluateCell<CR>', { buffer = buf, desc = 'Rerun current cell' })
    vim.keymap.set('x', '<CR>', ':<C-u>MoltenEvaluateVisual<CR>', { buffer = buf, desc = 'Run selected code' })
  end
  -- stylua: ignore end
end

-- Setup for existing buffers
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  setup_buf_keymaps_and_commands(buf)
end

vim.api.nvim_create_autocmd('FileType', {
  desc = 'Set buffer-local keymaps and commands for molten.',
  pattern = { 'python', 'markdown' },
  group = groupid,
  callback = function(info)
    setup_buf_keymaps_and_commands(info.buf)
  end,
})

---Set default highlight groups for headlines.nvim
---@return nil
local function set_default_hlgroups()
  local hl = require('utils.hl')
  hl.set(0, 'MoltenCell', { link = 'CursorLine' })
  hl.set(0, 'MoltenOutputWin', { link = 'Comment' })
  hl.set(0, 'MoltenOutputWinNC', { link = 'Comment' })
end
set_default_hlgroups()

vim.api.nvim_create_autocmd('ColorScheme', {
  group = groupid,
  desc = 'Set default highlight groups for headlines.nvim.',
  callback = set_default_hlgroups,
})
