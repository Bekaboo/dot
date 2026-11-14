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
end)
