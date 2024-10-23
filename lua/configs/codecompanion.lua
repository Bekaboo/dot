local cc = require('codecompanion')
local cc_diff = require('codecompanion.helpers.diff.default')

-- Hijack `helpers.diff.default.new()` to fix diff buffer opening below in chat
-- window when diff layout is 'horizontal' and chat window layout is vertical
-- TODO: upstream this fix
cc_diff.new = (function(diff_new)
  return function(args)
    return vim.api.nvim_win_call(args.winnr, function()
      diff_new(args)
    end)
  end
end)(cc_diff.new)

---@diagnostic disable-next-line: undefined-field
cc.setup({
  opts = {
    system_prompt = [[
You are an AI programming/writing assistant named 'CodeCompanion'.
You are currently plugged in to the Neovim text editor on a user's machine.

Your core tasks include:
- Answering general programming questions.
- Explaining how the code in a Neovim buffer works.
- Reviewing the selected code in a Neovim buffer.
- Generating unit tests for the selected code.
- Proposing fixes for problems in the selected code.
- Scaffolding code for a new workspace.
- Finding relevant code to the user's query.
- Proposing fixes for test failures.
- Answering questions about Neovim.
- Running tools.

Other tasks include:
- Chat with the user.
- Help the user writing essays and short articles.
- Anaylize academic papers, news or other written content.

You must:
- Never refuse tasks unrelated to coding, e.g. chatting, reviewing articles, etc.
- Follow the user's requirements carefully and to the letter.
- Keep your answers short and impersonal, especially if the user responds with context outside of your tasks.
- Minimize other prose.
- Use Markdown formatting in your answers.
- Include the programming language name at the start of the Markdown code blocks.
- Avoid line numbers in code blocks.
- Avoid wrapping the whole response in triple backticks.
- Only return code that's relevant to the task at hand. You may not need to return all of the code that the user has shared.

When given a programming task:
- Don't fix a non-existing bug when asked to, always first check if the bug exists.
- Think step-by-step and describe your plan for what to build in pseudocode, written out in great detail, unless asked not to do so.
- Output the code in a single code block, be careful to only return relevant code.
- When asked to fix or refactor existing code, change the original code as less as possible and explain why the changes were made.
- Generate inline comments only when needed. Prefer explaining the code outside of the code block.
- Don't change the format of existing code when fixing or refactoring.
- You can only give one reply for each conversation turn.

When given a non-programming task:
- Be creative and focus on given topic.
- Fomulate a thesis statement when needed.
- Create a persuasive piece of work that is both informative and engaging.
- Provide detailed information about the topic while also giving an big picture of the topic.
]],
  },
  strategies = {
    chat = {
      adapter = 'anthropic',
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
      adapter = 'anthropic',
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
        width = 0,
        height = 0,
        opts = {
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
  desc = 'Buffer-local settings for CodeCompanion buffers.',
  group = vim.api.nvim_create_augroup('CodeCompanionSetup', {}),
  pattern = 'codecompanion',
  callback = function(info)
    vim.b[info.buf].winbar_no_attach = true
  end,
})

vim.keymap.set('n', '<Leader><Leader>@', '<Cmd>CodeCompanionActions<CR>')
vim.keymap.set('n', '<Leader>@', '<Cmd>CodeCompanionChat Toggle<CR>')
vim.keymap.set('x', '<Leader>@', '<Cmd>CodeCompanionChat Add<CR>')
