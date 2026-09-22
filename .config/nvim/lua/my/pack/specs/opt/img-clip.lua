---@type my.pack.spec
return {
  src = 'https://github.com/HakonHarnes/img-clip.nvim',
  data = {
    load = function(spec, path)
      local load = require('my.utils.load')

      local function load_img_clip()
        if spec.data and spec.data.preload then
          spec.data.preload(spec, path)
        end
        load.load('img-clip.nvim')
        if spec.data and spec.data.postload then
          spec.data.postload(spec, path)
        end
      end

      if vim.v.vim_did_enter then
        vim.schedule(load_img_clip)
      else
        load.on_events('UIEnter', 'img-clip', vim.schedule_wrap(load_img_clip))
      end
    end,
    postload = function()
      local img_clip = require('img-clip')
      local img_clip_clipboard = require('img-clip.clipboard')
      local img_clip_config = require('img-clip.config')
      local img_clip_utils = require('img-clip.util')
      local utils = require('my.utils')

      ---Parse the first local file URI from clipboard output
      ---@param output string
      ---@return string?
      local function parse_file_uri(output)
        for line in output:gmatch('[^\n]+') do
          line = line:gsub('\r$', ''):gsub('%z+$', '')
          if line:match('^file:///') then
            local ok, path = pcall(vim.uri_to_fname, line)
            if ok then
              return path
            end
          end
        end
      end

      ---Get a copied file path from the macOS clipboard
      ---@return string?
      local function macos_clipboard_path()
        local result = vim
          .system({
            'osascript',
            '-e',
            'on run',
            '-e',
            'POSIX path of (the clipboard as \194\171class furl\194\187)',
            '-e',
            'end run',
          }, { text = true })
          :wait()

        if result.code ~= 0 or not result.stdout then
          return nil
        end

        return result.stdout:match('^([^\r\n]+)')
      end

      ---Get clipboard target types for a Linux clipboard command
      ---@param command string
      ---@return table<string, boolean>
      local function linux_clipboard_types(command)
        local args
        if command == 'wl-paste' then
          args = { 'wl-paste', '--list-types' }
        else
          args = { 'xclip', '-selection', 'clipboard', '-t', 'TARGETS', '-o' }
        end

        local types = {}
        local result = vim.system(args, { text = true }):wait()
        if result.code ~= 0 or not result.stdout then
          return types
        end

        for target in result.stdout:gmatch('[^\r\n]+') do
          types[target] = true
        end
        return types
      end

      ---Get a copied file path from a Linux clipboard
      ---@param command string
      ---@return string?
      local function linux_clipboard_path(command)
        local types = linux_clipboard_types(command)
        for _, target in ipairs({
          'x-special/gnome-copied-files',
          'text/uri-list',
        }) do
          if types[target] then
            local args
            if command == 'wl-paste' then
              args = { 'wl-paste', '--type', target }
            else
              args = {
                'xclip',
                '-selection',
                'clipboard',
                '-t',
                target,
                '-o',
              }
            end

            local result = vim.system(args, { text = true }):wait()
            if result.code == 0 and result.stdout then
              local path = parse_file_uri(result.stdout)
              if path then
                return path
              end
            end
          end
        end
      end

      ---Get the original image name from a copied file
      ---@return string?
      local function clipboard_image_name()
        local command = img_clip_clipboard.get_clip_cmd()
        local path
        if command == 'pngpaste' then
          path = macos_clipboard_path()
        elseif command == 'wl-paste' or command == 'xclip' then
          path = linux_clipboard_path(command)
        end

        if not path or path:find('%c') then
          return nil
        end

        local stat = vim.uv.fs_stat(path)
        if
          not stat
          or stat.type ~= 'file'
          or not img_clip_utils.is_image_path(path)
        then
          return nil
        end

        local name = vim.fn.fnamemodify(path, ':t:r')
        if name == '' or name:find('%c') then
          return nil
        end

        return name
      end

      ---Get the default name for a pasted image
      ---@return string
      local function default_file_name()
        return clipboard_image_name() or os.date('%Y-%m-%d-%H-%M-%S') --[[@as string]]
      end

      ---Get indentation string
      ---@return string
      local function indent()
        return utils.snip.funcs.get_indent_str(1)
      end

      img_clip.setup({
        default = {
          insert_mode_after_paste = false,
          use_cursor_in_template = true,
          dir_path = function()
            local bufname = vim.api.nvim_buf_get_name(0)
            local img_dir = (
              unpack(vim.fs.find({
                'img',
                'imgs',
                'image',
                'images',
                'pic',
                'pics',
                'picture',
                'pictures',
                'asset',
                'assets',
              }, {
                path = vim.fs.dirname(bufname),
                upward = true,
              }))
            )

            -- Don't save images to `~/pictures` under home directory
            if
              not img_dir or utils.fs.is_home_dir(vim.fs.dirname(img_dir))
            then
              img_dir = vim.fs.joinpath(vim.fs.dirname(bufname), 'img')
            end

            return vim.fn.fnamemodify(
              vim.fs.joinpath(img_dir, vim.fn.fnamemodify(bufname, ':t:r')),
              ':.'
            )
          end,
        },
        filetypes = {
          markdown = { template = '![$LABEL$CURSOR]($FILE_PATH)' },
          vimwiki = { template = '![$LABEL$CURSOR]($FILE_PATH)' },
          html = { template = '<img src="$FILE_PATH" alt="$LABEL$CURSOR">' },
          asciidoc = {
            template = 'image::$FILE_PATH[width=80%, alt="$LABEL$CURSOR"]',
          },
          tex = {
            template = function()
              return ([[
\begin{figure}[H]
$INDENT\centering
$INDENT\includegraphics[width=1.0\textwidth]{$FILE_PATH}
\label{fig:$LABEL}
\caption{$CURSOR}
\end{figure}
]]):gsub('$INDENT', indent())
            end,
          },
          typst = {
            template = function()
              return ([[
#figure(
$INDENTimage("$FILE_PATH", width: 80%),
$INDENTcaption: [$LABEL$CURSOR],
) <fig-$LABEL>
]]):gsub('$INDENT', indent())
            end,
          },
          rst = {
            template = [[
.. image:: $FILE_PATH
   :alt: $LABEL$CURSOR
   :width: 80%
]],
          },
          org = {
            template = [=[
#+BEGIN_FIGURE
[[file:$FILE_PATH]]
#+CAPTION: $LABEL$CURSOR
#+NAME: fig:$LABEL
#+END_FIGURE
]=],
          },
        },
      })

      local img_clip_input = img_clip_utils.input

      ---Hijack `img-clip.util.input()` to add the resolved image name to the
      ---filename prompt
      ---@param args table<string, any>
      ---@return string?
      ---@diagnostic disable-next-line: duplicate-set-field
      img_clip_utils.input = function(args)
        if args.prompt ~= 'File name: ' or args.default ~= nil then
          return img_clip_input(args)
        end

        args = vim.tbl_extend('force', {}, args, {
          default = default_file_name(),
        })

        local img_name = img_clip_input(args)
        -- User cancels pasting
        if img_name == '' then
          return nil
        end

        return img_name
      end

      ---@type table<string, any>
      local filetypes = require('img-clip.config').opts.filetypes

      ---Setup keymaps for img-clip
      ---@param buf integer?
      ---@return nil
      local function setup_keymaps(buf)
        buf = vim._resolve_bufnr(buf)
        if filetypes[vim.bo[buf].ft] then
          vim.keymap.set('n', '<Leader>p', img_clip.paste_image, {
            buffer = buf,
            desc = 'Paste image',
          })
        end
      end

      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        setup_keymaps(buf)
      end

      vim.api.nvim_create_autocmd('FileType', {
        desc = 'Buffer-local settings for img-clip.',
        group = vim.api.nvim_create_augroup('my.img-clip', {}),
        pattern = vim.tbl_keys(filetypes),
        callback = function(args)
          setup_keymaps(args.buf)
        end,
      })
    end,
  },
}
