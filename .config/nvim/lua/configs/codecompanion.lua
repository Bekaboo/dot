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
        options = {
          modes = { n = 'g?' },
          callback = 'keymaps.options',
          description = 'Options',
          hide = true,
        },
        close = {
          modes = { n = 'gX', i = '<M-C-X>' },
          index = 3,
          callback = 'keymaps.close',
          description = 'Close Chat',
        },
        stop = {
          modes = { n = '<C-c>' },
          index = 4,
          callback = 'keymaps.stop',
          description = 'Stop Request',
        },
        codeblock = {
          modes = { n = 'cdb' },
          index = 6,
          callback = 'keymaps.codeblock',
          description = 'Insert Codeblock',
        },
        next_chat = {
          modes = { n = ']}' },
          index = 8,
          callback = 'keymaps.next_chat',
          description = 'Next Chat',
        },
        previous_chat = {
          modes = { n = '[{' },
          index = 9,
          callback = 'keymaps.previous_chat',
          description = 'Previous Chat',
        },
        clear = {
          modes = { n = 'gC' },
          index = 5,
          callback = 'keymaps.clear',
          description = 'Clear Chat',
        },
        fold_code = {
          modes = { n = 'gF' },
          index = 13,
          callback = 'keymaps.fold_code',
          description = 'Fold code',
        },
      },
    },
    inline = {
      adapter = adapter,
      keymaps = {
        accept_change = {
          modes = { n = 'gA' },
          index = 1,
          callback = 'keymaps.accept_change',
          description = 'Accept change',
        },
        reject_change = {
          modes = { n = 'gX' },
          index = 2,
          callback = 'keymaps.reject_change',
          description = 'Reject change',
        },
      },
    },
  },
  display = {
    chat = {
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

-- Set filetype to 'markdown' only in codecompanion chat buffers in normal mode for integration
local groupid = vim.api.nvim_create_augroup('CodeCompanionFtHack', {})
vim.api.nvim_create_autocmd('FileType', {
  group = groupid,
  pattern = 'codecompanion',
  callback = vim.schedule_wrap(function(info)
    if not vim.startswith(vim.fn.mode(), 'i') then
      vim.bo[info.buf].ft = 'markdown'
    end
  end),
})
vim.api.nvim_create_autocmd('InsertEnter', {
  group = groupid,
  pattern = '*\\[CodeCompanion\\]*',
  callback = function(info)
    if vim.bo[info.buf].bt == '' then
      return
    end
    vim.bo[info.buf].ft = 'codecompanion'
  end,
})
vim.api.nvim_create_autocmd('InsertLeave', {
  group = groupid,
  pattern = '*\\[CodeCompanion\\]*',
  callback = function(info)
    if vim.bo[info.buf].bt == '' then
      return
    end
    vim.bo[info.buf].ft = 'markdown'
  end,
})

-- stylua: ignore start
vim.keymap.set('n', '<Leader><Leader>@', '<Cmd>CodeCompanionActions<CR>', { desc = 'Pick AI actions' })
vim.keymap.set('n', '<Leader>@', '<Cmd>CodeCompanionChat Toggle<CR>', { desc = 'Chat with AI assistant' })
vim.keymap.set('x', '<Leader>@', '<Cmd>CodeCompanionChat Add<CR>', { desc = 'Add selection to conversation with AI' })
vim.keymap.set('n', '<Leader>+', '<Cmd>CodeCompanion<CR>', { desc = 'Inline AI help' })
-- stylua: ignore end
