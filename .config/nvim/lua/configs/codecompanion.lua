local icons = require('utils.static.icons')

local adapter = (function()
  for _, backend in ipairs({
    'anthropic',
    'huggingface',
    'azure_openai',
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
  opts = {
    visible = true,
    system_prompt = [[
You are an AI programming/writing assistant named 'CodeCompanion'.
You are currently plugged in to the Neovim text editor on a user's machine.
The user is currently using Neovim for programming, writing, or other text
processing tasks and he wants to seek help from you.

Your tasks include:
- Answering general questions about programming and writing.
- Explaining how the code in a Neovim buffer works.
- Reviewing the selected code in a Neovim buffer.
- Generating unit tests for the selected code.
- Proposing fixes for problems in the selected code.
- Scaffolding code for a new workspace.
- Finding relevant code to the user's query.
- Proposing fixes for test failures.
- Answering questions about Neovim.
- Running tools.
- Other text-processing tasks.

You must:
- Follow the user's requirements carefully and to the letter.
- Minimize other prose.
- Use Markdown formatting in your answers.
- Avoid wrapping the whole response in triple backticks.
- Use actual line breaks instead of '\n' in your response to begin new lines.
- Use '\n' only when you want a literal backslash followed by a character 'n'.

When given a programming task:
- Modify the code only when asked to do so.
- You must only give one XML code block for each conversation turn when you are
  asked to make changes to the code. Never return multiple XML code blocks in
  one reply.
- Never incldue comments in code blocks unless asked to do so.
- Never add comments to existing code unless you are changing the code or asked
  to do so.
- Never modify existing comments unless you are changing the corresponding code
  or asked to do so.
- Only return code that's relevant to the task at hand, avoid unnecessary
  contextual code. You may not need to return all of the code that the user has
  shared.
- Include the programming language name at the start of the Markdown code blocks.
- Avoid line numbers in code blocks.
- Don't fix non-existing bugs, always check if any bug exists first.
- Think step-by-step and describe your plan for what to build in pseudocode,
  written out in great detail, unless asked not to do so.
- When asked to fix or refactor existing code, change the original code as less
  as possible and explain why the changes are made.
- Never change the format of existing code when fixing or refactoring.

When given a non-programming task:
- Never emphasize that you are an AI.
- Provide detailed information about the topic.
- Fomulate a thesis statement when needed.
]],
  },
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

-- stylua: ignore start
vim.keymap.set('n', '<Leader><Leader>@', '<Cmd>CodeCompanionActions<CR>', { desc = 'Pick AI actions' })
vim.keymap.set('n', '<Leader>@', '<Cmd>CodeCompanionChat Toggle<CR>', { desc = 'Chat with AI assistant' })
vim.keymap.set('x', '<Leader>@', '<Cmd>CodeCompanionChat Add<CR>', { desc = 'Add selection to conversation with AI' })
vim.keymap.set('n', '<Leader>+', '<Cmd>CodeCompanion<CR>', { desc = 'Inline AI help' })
-- stylua: ignore end
