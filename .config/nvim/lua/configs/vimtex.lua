if vim.env.TERM == 'linux' then
  vim.g.vimtex_syntax_conceal_disable = true
end

-- Enable vim's legacy regex-based syntax highlighting alongside treesitter
-- highlighting for some vimtex functions, e.g. changing modifiers, formatting,
-- indentation, etc.
vim.treesitter.start = (function(cb)
  ---@param bufnr integer? Buffer to be highlighted (default: current buffer)
  ---@param lang string? Language of the parser (default: from buffer filetype)
  return function(bufnr, lang, ...)
    bufnr = vim._resolve_bufnr(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    cb(bufnr, lang, ...)
    -- Re-enable regex syntax highlighting after starting treesitter
    if vim.bo[bufnr].ft == 'tex' or lang == 'latex' then
      vim.bo[bufnr].syntax = 'on'
    end
  end
end)(vim.treesitter.start)

vim.g.vimtex_quickfix_mode = 0
vim.g.vimtex_format_enabled = 1
vim.g.vimtex_imaps_enabled = 0
vim.g.vimtex_mappings_prefix = '<LocalLeader>l'

-- Time to defer before doing automatic forward search, i.e. sync viewer with
-- nvim tex source file
vim.g.vimtex_auto_sync_view_debounce = 500

-- Explicitly set view method for forward and inverse search
if vim.fn.executable('zathura') == 1 then
  vim.g.vimtex_view_method = 'zathura'
  vim.g.vimtex_auto_sync_view_debounce = 0
elseif vim.fn.executable('okular') == 1 then
  vim.g.vimtex_view_general_viewer = 'okular'
  vim.g.vimtex_view_general_options = '--unique file:@pdf#src:@line@tex'
end

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'tex',
  group = vim.api.nvim_create_augroup('vim.plugin.vimtex.ft', {}),
  callback = function(args)
    -- Make surrounding delimiters large
    vim.keymap.set('n', 'css', vim.fn['vimtex#delim#add_modifiers'], {
      buffer = args.buf,
      desc = 'Surround with large delimiters',
    })
    -- Remove default `]]` mapping in insert mode as it causes lagging
    -- when typing `]`
    pcall(vim.keymap.del, 'i', ']]', {
      buffer = args.buf,
    })

    -- Automatically sync pdf viewer with tex source file
    vim.api.nvim_create_autocmd('CursorMoved', {
      desc = 'Automatically sync pdf viewer with tex source file.',
      buffer = args.buf,
      group = vim.api.nvim_create_augroup(
        'my.vimtex.auto_sync_view.buf.' .. args.buf,
        {}
      ),
      callback = function(a)
        local viewer_name = vim.b[a.buf].vimtex.viewer.name
        if viewer_name == 'General' then
          viewer_name = vim.g.vimtex_view_general_viewer
        end
        if not viewer_name then
          return
        end

        local auto_sync_view_request_time = vim.uv.now()
        vim.g._vimtex_auto_sync_view_request_time = auto_sync_view_request_time

        ---Check if the previous should be updated
        ---
        ---The preview should be updated if
        ---  - current cursor line has changed
        ---  - current request is the latest request sent
        ---  - current buffer is a tex buffer
        ---@return boolean
        local function should_update_preview()
          return vim.fn.line('.') ~= vim.g._vimtex_auto_sync_view_source_line
            and vim.g._vimtex_auto_sync_view_request_time == auto_sync_view_request_time
            and vim.api.nvim_get_current_buf() == a.buf
        end

        -- Skip spawning a viewer; only sync if a viewer window already exists
        -- Some examples of `ps fp $(pgrep ...)` command output (stdout):
        -- zathura: zathura -x /usr/bin/nvim --headless -c "VimtexInverseSearch %{line}:%{column} '%{input}'" --synctex-forward 62:1:/home/user/test.tex test.pdf
        -- okular:  okular --unique file:/home/user/test.pdf#src:74/home/user/test.tex
        vim.defer_fn(function()
          if not should_update_preview() then
            return
          end

          local out_pdf =
            vim.F.npcall(vim.api.nvim_eval, 'b:vimtex.viewer.out()')
          if not out_pdf then
            return
          end

          vim.system(
            {
              'pgrep',
              '-if',
              string.format(
                '%s.*%s.*%s',
                viewer_name,
                -- Don't match against `vim.api.nvim_buf_get_name(a.buf)` here
                -- as nvim can be inside another tex file in a tex project with
                -- multiple tex files, e.g. (main.tex, section1.tex,
                -- section2.tex, etc.)
                vim.fs.dirname(out_pdf),
                vim.fs.basename(out_pdf)
              ),
            },
            {},
            vim.schedule_wrap(function(out)
              if out.stdout == '' or not should_update_preview() then
                return
              end
              vim.fn['vimtex#view#view']()
              vim.g._vimtex_auto_sync_view_source_line = vim.fn.line('.')
            end)
          )
        end, vim.g.vimtex_auto_sync_view_debounce)
      end,
    })
  end,
})
