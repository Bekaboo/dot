local stl = require('my.utils.stl')

---@param str string
---@return string
local function render(str)
  return vim.api.nvim_eval_statusline(str, {}).str
end

describe('[utils][stl]', function()
  describe('hl', function()
    it('returns the string as a statusline highlight item', function()
      assert.are.same('%#Error#foo%*', stl.hl('foo', 'Error'))
      -- The highlight is left on for what comes next when not restoring
      assert.are.same('%#Error#foo', stl.hl('foo', 'Error', false))
    end)
    it('defaults to an empty highlight group and empty string', function()
      assert.are.same('%##foo%*', stl.hl('foo'))
      assert.are.same('%#Error#%*', stl.hl(nil, 'Error'))
    end)
    it('renders with the given highlight group', function()
      local rendered = vim.api.nvim_eval_statusline(
        stl.hl('foo', 'Error'),
        { highlights = true }
      )
      assert.are.same('foo', rendered.str)
      assert.are.same('Error', rendered.highlights[1].group)
    end)
  end)

  describe('make_clickable', function()
    it('returns the string as a clickable statusline item', function()
      assert.are.same(
        '%@v:lua.cb@foo%X',
        stl.make_clickable('foo', 'v:lua.cb')
      )
    end)
    it('renders as the plain text', function()
      assert.are.same(
        'foo',
        render(stl.make_clickable('foo', 'v:lua.require_my_plugin_cb'))
      )
    end)
  end)

  describe('escape', function()
    it('doubles percentage signs', function()
      assert.are.same('100%% done', stl.escape('100% done'))
      assert.are.same('foo', stl.escape('foo'))
    end)
    it('makes the string safe to evaluate in a statusline', function()
      -- Evaluating an unescaped `%` raises E539
      assert.has_error(function()
        vim.api.nvim_eval_statusline('100% done', {})
      end)
      assert.are.same('100% done', render(stl.escape('100% done')))
    end)
  end)
  describe('spinner', function()
    -- Frames that do not advance during a test and a short finish timeout keep
    -- the state transitions deterministic
    local default_opts = {
      frame_interval = 10000,
      finish_timeout = 20,
      icons = {
        progress = { 'a', 'b' },
        finish = 'done',
      },
    }

    local created = {} ---@type my.stl.spinner[]

    ---@param opts my.stl.spinner.opts?
    ---@return my.stl.spinner
    local function new_spinner(opts)
      local spinner =
        stl.spinner:new(vim.tbl_deep_extend('force', default_opts, opts or {}))
      table.insert(created, spinner)
      return spinner
    end

    after_each(function()
      for _, spinner in ipairs(created) do
        if stl.spinner.id_is_valid(spinner.id) then
          spinner:del()
        end
      end
      created = {}
    end)

    it('starts in the idle state', function()
      local spinner = new_spinner()
      assert.are.same('idle', spinner.status)
      assert.are.same('', spinner.icon)
      assert.is_true(stl.spinner.id_is_valid(spinner.id))
      assert.are.equal(spinner, stl.spinner.get_by_id(spinner.id))
    end)
    it('shows a progress icon while spinning', function()
      local spinner = new_spinner()
      spinner:spin()
      assert.are.same('spinning', spinner.status)
      assert.is_true(vim.tbl_contains({ 'a', 'b' }, spinner.icon))
    end)
    it(
      'shows the finish icon, then clears it after the finish timeout',
      function()
        local spinner = new_spinner()
        spinner:spin()
        spinner:finish()
        assert.are.same('finish', spinner.status)
        assert.are.same('done', spinner.icon)

        vim.wait(500, function()
          return spinner.status == 'idle'
        end)
        assert.are.same('idle', spinner.status)
        assert.are.same('', spinner.icon)
      end
    )
    it(
      'does not interrupt the finish icon before the finish timeout',
      function()
        local spinner = new_spinner({ finish_timeout = 10000 })
        spinner:spin()
        spinner:finish()
        spinner:spin()
        assert.are.same('finish', spinner.status)
        assert.are.same('done', spinner.icon)
      end
    )
    it('only finishes a spinning spinner', function()
      local spinner = new_spinner()
      spinner:finish()
      assert.are.same('idle', spinner.status)
      assert.are.same('', spinner.icon)
    end)
    it('deletes itself', function()
      local spinner = new_spinner()
      local id = spinner.id
      spinner:del()
      assert.is_false(stl.spinner.id_is_valid(id))
      assert.is_nil(stl.spinner.get_by_id(id))
    end)
    it('reports unknown ids', function()
      assert.is_nil(stl.spinner.get_by_id(nil))
      assert.is_false(stl.spinner.id_is_valid(nil))
      assert.is_nil(stl.spinner.get_by_id(-1))
      assert.is_false(stl.spinner.id_is_valid(-1))
    end)
    it('attaches to a buffer', function()
      local buf = vim.api.nvim_get_current_buf()
      local spinner = new_spinner()
      spinner:attach(buf)
      assert.are.same(spinner.id, vim.b[buf].spinner_id)
    end)
    it('detaches from a buffer and deletes itself', function()
      local buf = vim.api.nvim_get_current_buf()
      local spinner = new_spinner()
      spinner:attach(buf)
      local id = spinner.id
      spinner:detach()
      assert.is_nil(vim.b[buf].spinner_id)
      assert.is_false(stl.spinner.id_is_valid(id))
    end)
    it('detaches without deleting itself when asked to', function()
      local buf = vim.api.nvim_get_current_buf()
      local spinner = new_spinner()
      spinner:attach(buf)
      spinner:detach(false)
      assert.is_nil(vim.b[buf].spinner_id)
      assert.is_true(stl.spinner.id_is_valid(spinner.id))
    end)
    it('replaces the spinner attached to a buffer', function()
      local buf = vim.api.nvim_get_current_buf()
      local first = new_spinner()
      local second = new_spinner()
      first:attach(buf)
      second:attach(buf)
      assert.are.same(second.id, vim.b[buf].spinner_id)
      assert.is_false(stl.spinner.id_is_valid(first.id))
    end)
  end)
end)
