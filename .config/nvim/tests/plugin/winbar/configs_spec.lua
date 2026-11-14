local winbar = require('my.plugin.winbar')
local configs = require('my.plugin.winbar.configs')

describe('[winbar][configs]', function()
  local buf = nil ---@type integer
  local win = nil ---@type integer
  local saved_opts = nil ---@type my.winbar.config.opts

  before_each(function()
    buf = vim.api.nvim_get_current_buf()
    win = vim.api.nvim_get_current_win()
    -- Options are mutated in place by `setup()`, restore them afterwards
    saved_opts = vim.deepcopy(configs.opts)
    -- Allow `setup()` to register autocmds again for each test
    vim.g.loaded_winbar = nil
    vim.api.nvim_create_augroup('my.winbar', { clear = true })
  end)

  after_each(function()
    configs.opts = saved_opts
  end)

  describe('bar.enable', function()
    local function enabled()
      return configs.eval(configs.opts.bar.enable, buf, win)
    end

    it('is enabled for markdown buffers', function()
      vim.bo[buf].filetype = 'markdown'
      assert.is_true(enabled())
    end)
    it('is disabled for terminal buffers', function()
      vim.cmd.terminal()
      local term_buf = vim.api.nvim_get_current_buf()
      local term_win = vim.api.nvim_get_current_win()
      assert.are.same('terminal', vim.bo[term_buf].bt) -- precondition
      assert.is_false(
        configs.eval(configs.opts.bar.enable, term_buf, term_win)
      )
      vim.api.nvim_buf_delete(term_buf, { force = true })
    end)
    it('is disabled if the window already has a winbar', function()
      vim.bo[buf].filetype = 'markdown'
      vim.wo[win].winbar = 'custom'
      assert.is_false(enabled())
      vim.wo[win].winbar = ''
    end)
    it('is disabled per buffer or per window', function()
      vim.bo[buf].filetype = 'markdown'
      vim.b[buf].winbar_no_attach = true
      assert.is_false(enabled())
      vim.b[buf].winbar_no_attach = nil

      vim.w[win].winbar_no_attach = true
      assert.is_false(enabled())
      vim.w[win].winbar_no_attach = nil
    end)
  end)

  describe('setup', function()
    it('registers autocmds for the configured events', function()
      winbar.setup({
        bar = {
          update_events = {
            win = { 'CursorMoved' },
            buf = {},
            global = {
              {
                event = 'OptionSet',
                pattern = 'modified',
              },
            },
          },
        },
      })
      local function autocmds(event)
        return vim.api.nvim_get_autocmds({
          group = 'my.winbar',
          event = event,
        })
      end

      -- Structured events keep their pattern
      assert.are.same(1, #autocmds('OptionSet'))
      assert.are.same('modified', autocmds('OptionSet')[1].pattern)

      -- Simple events are registered for all patterns
      assert.are.same(1, #autocmds('CursorMoved'))
      assert.are.same('*', autocmds('CursorMoved')[1].pattern)

      -- Events that are not configured are not registered
      assert.are.same(0, #autocmds('TextChanged'))
    end)
    it('registers autocmds only once', function()
      winbar.setup()
      winbar.setup()
      assert.are.same(1, #vim.api.nvim_get_autocmds({
        group = 'my.winbar',
        event = 'BufEnter',
      }))
    end)
    it('applies config changes on subsequent calls', function()
      winbar.setup({ bar = { padding = { left = 2 } } })
      winbar.setup({ bar = { padding = { right = 3 } } })
      assert.are.same({ left = 2, right = 3 }, configs.opts.bar.padding)
    end)
  end)

  describe('eval', function()
    it('evaluates callable options with the given arguments', function()
      assert.are.same(
        { 1, 2 },
        configs.eval(function(...)
          return { ... }
        end, 1, 2)
      )
    end)
    it('returns non-callable options as is', function()
      local opts = { a = 1 }
      assert.are.equal(opts, configs.eval(opts, 1, 2))
      assert.is_true(configs.eval(true, 1, 2))
      assert.is_false(configs.eval(false, 1, 2))
      assert.is_nil(configs.eval(nil, 1, 2))
    end)
  end)
end)
