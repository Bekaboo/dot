vim.bo.sw = 4
vim.bo.cindent = false
vim.bo.smartindent = false
vim.bo.commentstring = '<!-- %s -->'

---Don't join title/first line of list item with previous lines when yanking
---with joined paragraphs
---@param line string
---@return boolean
---@diagnostic disable-next-line: duplicate-set-field
function vim.b.should_join_line(line)
  return line ~= ''
    and not line:match('^%s*[-*#]%s+')
    and not line:match('^%s*%d+%.%s+')
end

-- Map `[[`/`]]` in both normal & visual mode
-- (default shipped `ftplugin/markdown.lua` only maps in normal node)
vim.keymap.set({ 'n', 'x' }, ']]', function()
  require('vim.treesitter._headings').jump({ count = 1 })
end, {
  buf = 0,
  silent = false,
  desc = 'Jump to next section',
})

vim.keymap.set({ 'n', 'x' }, '[[', function()
  require('vim.treesitter._headings').jump({ count = -1 })
end, {
  buf = 0,
  silent = false,
  desc = 'Jump to previous section',
})
