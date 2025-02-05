local icons = require('utils.static.icons')

local adapter = (function()
  for _, backend in ipairs({
    'anthropic',
    'azure_openai',
    'deepseek',
    'huggingface',
    'openai',
    'gemini',
    'xai',
  }) do
    if vim.env[backend:upper() .. '_API_KEY'] then
      return backend
    end
  end
end)()

---@diagnostic disable-next-line: undefined-field
require('codecompanion').setup({
  opts = { visible = true },
  strategies = {
    chat = {
      adapter = adapter,
      slash_commands = {
        ['file'] = { opts = { provider = 'fzf_lua' } },
        ['help'] = { opts = { provider = 'fzf_lua' } },
      },
      keymaps = {
        options = { modes = { n = 'g?' } },
        close = { modes = { n = 'gX', i = '<M-C-X>' } },
        stop = { modes = { n = '<C-c>' } },
        codeblock = { modes = { n = 'cdb' } },
        next_header = { modes = { n = ']#' } },
        previous_header = { modes = { n = '[#' } },
        next_chat = { modes = { n = ']}' } },
        previous_chat = { modes = { n = '[{' } },
        clear = { modes = { n = 'gC' } },
        fold_code = { modes = { n = 'gF' } },
        debug = { modes = { n = 'g<C-g>' } },
        change_adapter = { modes = { n = 'gA' } },
        system_prompt = { modes = { n = 'gS' } },
        pin = {
          modes = { n = 'g>' },
          description = 'Pin Reference (resend whole contents on change)',
        },
        watch = {
          modes = { n = 'g=' },
          description = 'Watch Buffer (send diffs on change)',
        },
      },
    },
    inline = {
      adapter = adapter,
      keymaps = {
        accept_change = {
          modes = { n = 'gA' },
          callback = 'keymaps.accept_change',
        },
        reject_change = {
          modes = { n = 'gX' },
          callback = 'keymaps.reject_change',
        },
      },
    },
  },
  display = {
    chat = {
      icons = {
        pinned_buffer = icons.Pin,
        watched_buffer = icons.Eye,
      },
      intro_message = 'Welcome to CodeCompanion! Press `g?` for options',
      window = {
        layout = 'vertical',
        opts = {
          winbar = '', -- disable winbar in codecompanion chat buffers
          statuscolumn = '',
          foldcolumn = '0',
          linebreak = true,
          breakindent = true,
          wrap = true,
          spell = true,
          number = false,
        },
      },
    },
    diff = {
      close_chat_at = 0,
      layout = 'horizontal',
    },
    inline = {
      layout = 'horizontal',
    },
  },
})

vim.api.nvim_create_autocmd('FileType', {
  desc = 'Set filetype to "markdown" in codecompanion chat buffer shortly for integration.',
  group = vim.api.nvim_create_augroup('CodeCompanionFtHack', {}),
  pattern = 'codecompanion',
  callback = vim.schedule_wrap(function(info)
    local buf = info.buf
    if vim.b[buf]._cc_ft_hack then
      return
    end
    vim.b[buf]._cc_ft_hack = true
    vim.bo[buf].ft = 'markdown'
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        vim.bo[buf].ft = 'codecompanion'
      end
    end)
  end),
})

vim.api.nvim_create_autocmd('FileType', {
  desc = 'Clear welcome messages on text change in codecompanion chat buffers.',
  group = vim.api.nvim_create_augroup('CodeCompanionClearWelcomeMsg', {}),
  pattern = 'codecompanion',
  callback = vim.schedule_wrap(function(info)
    vim.api.nvim_create_autocmd('TextChanged', {
      once = true,
      buffer = info.buf,
      callback = function(i)
        local ns = vim.api.nvim_get_namespaces()['CodeCompanion-intro_message']
        if ns then
          vim.api.nvim_buf_clear_namespace(i.buf, ns, 0, -1)
        end
        return true
      end,
    })
  end),
})

---Set default highlight groups for codecompanion.nvim
local function set_default_hlgroups()
  vim.api.nvim_set_hl(0, 'CodeCompanionChatVariable', { link = 'Special' })
  vim.api.nvim_set_hl(0, 'CodeCompanionChatAgent', { link = 'Constant' })
  vim.api.nvim_set_hl(0, 'CodeCompanionChatTool', { link = 'Operator' })
end

set_default_hlgroups()

vim.api.nvim_create_autocmd('ColorScheme', {
  desc = 'Set some default hlgroups for codecompanion.',
  group = vim.api.nvim_create_augroup('CodeCompanionSetDefaultHlgroups', {}),
  callback = set_default_hlgroups,
})

-- stylua: ignore start
vim.keymap.set('n', '<Leader>!', '<Cmd>CodeCompanionActions<CR>', { desc = 'AI actions' })
vim.keymap.set('n', '<Leader>@', '<Cmd>CodeCompanionChat Toggle<CR>', { desc = 'AI chat assistant' })
vim.keymap.set('x', '<Leader>@', '<Cmd>CodeCompanionChat Add<CR>', { desc = 'Add selection to conversation with AI' })
vim.keymap.set('n', '<Leader>+', '<Cmd>CodeCompanion<CR>', { desc = 'AI inline assistant' })
-- stylua: ignore end
