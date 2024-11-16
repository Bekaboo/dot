local img_clip = require('img-clip')

---Get indentation string
---@return string
local function indent()
  return require('utils.snippets.funcs').get_indent_str(1)
end

img_clip.setup({
  default = {
    insert_mode_after_paste = false,
    use_cursor_in_template = false,
    dir_path = function()
      local bufname = vim.api.nvim_buf_get_name(0)
      local img_basedir = (
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

      return vim.fs.joinpath(
        img_basedir and vim.fn.fnamemodify(img_basedir, ':~:.') or 'img',
        vim.fn.fnamemodify(bufname, ':t:r')
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
\begin{figure}[h]
$INDENT\centering
$INDENT\includegraphics[width=0.8\textwidth]{$FILE_PATH}
$INDENT\caption{$LABEL$CURSOR}
$INDENT\label{fig:$LABEL}
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

---@type table<string, true>
local filetypes = {}
for ft, _ in pairs(require('img-clip.config').opts.filetypes) do
  filetypes[ft] = true
end

---Setup keymaps for img-clip
---@param buf integer?
---@return nil
local function setup_keymaps(buf)
  buf = buf or 0
  if filetypes[vim.bo[buf].ft] then
    vim.keymap.set({ 'n', 'x' }, '<Leader>p', img_clip.paste_image, {
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
  group = vim.api.nvim_create_augroup('ImgClipSetup', {}),
  pattern = vim.tbl_keys(filetypes),
  callback = function(info)
    setup_keymaps(info.buf)
  end,
})
