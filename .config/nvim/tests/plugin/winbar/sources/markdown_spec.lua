local helpers = require('helpers')
local winbar_helpers = require('helpers.winbar')
local source_markdown = require('my.plugin.winbar.sources.markdown')

describe('[winbar][source][markdown]', function()
  before_each(function()
    helpers.edit_asset('headings.md')
  end)

  describe('symbol path', function()
    local function symbol_path_at(test_point)
      return winbar_helpers.symbol_names_at(source_markdown, test_point)
    end

    it('is correct with ordered headings', function()
      assert.are.same({ 'H1', 'H2', 'H3' }, symbol_path_at(1))
    end)
    it('is correct with headings with skipped levels', function()
      assert.are.same({ 'H1', 'H2', 'H3', 'H5' }, symbol_path_at(2))
    end)
    it('is correct with unordered headings', function()
      assert.are.same({ 'H1', 'H2', 'H3', 'H4' }, symbol_path_at(3))
    end)
    it('is correct with repeated heading levels', function()
      assert.are.same({ 'H1', 'H2', 'H3', 'H4', 'H6.2' }, symbol_path_at(4))
    end)
    it('ignores heading patterns inside code blocks', function()
      assert.are.same({ 'H1', 'H2.1' }, symbol_path_at(5))
    end)
  end)

  describe('symbol tree', function()
    it('has correct structure', function()
      local symbols = winbar_helpers.symbols_at(source_markdown, 0)
      local root = symbols[1]
      assert.are.same('H1', root.name)
      assert.are.same({
        H1 = {
          H2 = {
            H3 = {
              H5 = {},
              H4 = {
                H6 = {},
                ['H6.1'] = {},
                ['H6.2'] = {},
              },
            },
          },
          ['H2.1'] = {},
        },
      }, {
        [root.name] = winbar_helpers.children_tree(root),
      })
    end)
  end)
end)
