local lsp_utils = require('my.utils.lsp')

---Build a 0-indexed LSP range
---@param start_line integer
---@param start_character integer
---@param end_line integer
---@param end_character integer
---@return my.lsp.range
local function range(start_line, start_character, end_line, end_character)
  return {
    start = { line = start_line, character = start_character },
    ['end'] = { line = end_line, character = end_character },
  }
end

describe('[utils][lsp]', function()
  describe('range_contains', function()
    local outer = range(1, 0, 3, 5)

    local cases = {
      {
        desc = 'a range contained by the outer range',
        inner = range(1, 2, 3, 4),
        contained = true,
        strictly_contained = true,
      },
      {
        desc = 'a range identical to the outer range',
        inner = range(1, 0, 3, 5),
        contained = true,
        strictly_contained = false,
      },
      {
        desc = 'a range starting at the start of the outer range',
        inner = range(1, 0, 2, 0),
        contained = true,
        strictly_contained = false,
      },
      {
        desc = 'a range ending at the end of the outer range',
        inner = range(2, 0, 3, 5),
        contained = true,
        strictly_contained = false,
      },
      {
        desc = 'a range on a single line inside the outer range',
        inner = range(2, 1, 2, 4),
        contained = true,
        strictly_contained = true,
      },
      {
        desc = 'a range starting before the outer range',
        inner = range(0, 0, 2, 0),
        contained = false,
        strictly_contained = false,
      },
      {
        desc = 'a range ending after the outer range',
        inner = range(2, 0, 4, 0),
        contained = false,
        strictly_contained = false,
      },
      {
        desc = 'a range after the outer range',
        inner = range(4, 0, 5, 0),
        contained = false,
        strictly_contained = false,
      },
    }

    for _, case in ipairs(cases) do
      it(('contains %s'):format(case.desc), function()
        assert.are.same(
          case.contained,
          lsp_utils.range_contains(outer, case.inner)
        )
      end)
      it(('strictly contains %s'):format(case.desc), function()
        assert.are.same(
          case.strictly_contained,
          lsp_utils.range_contains(outer, case.inner, true)
        )
      end)
    end
  end)

  describe('range_contains_cursor', function()
    local outer = range(1, 0, 3, 5)

    -- Cursor positions are 1,0-indexed
    local cases = {
      {
        desc = 'a cursor inside the range',
        cursor = { 3, 3 },
        contained = true,
        strictly_contained = true,
      },
      {
        desc = 'a cursor at the start of the range',
        cursor = { 2, 0 },
        contained = true,
        strictly_contained = false,
      },
      {
        desc = 'a cursor at the end of the range',
        cursor = { 4, 5 },
        contained = true,
        strictly_contained = false,
      },
      {
        desc = 'a cursor before the range',
        cursor = { 1, 0 },
        contained = false,
        strictly_contained = false,
      },
      {
        desc = 'a cursor after the range',
        cursor = { 4, 6 },
        contained = false,
        strictly_contained = false,
      },
    }

    for _, case in ipairs(cases) do
      it(('contains %s'):format(case.desc), function()
        assert.are.same(
          case.contained,
          lsp_utils.range_contains_cursor(outer, case.cursor)
        )
      end)
      it(('strictly contains %s'):format(case.desc), function()
        assert.are.same(
          case.strictly_contained,
          lsp_utils.range_contains_cursor(outer, case.cursor, true)
        )
      end)
    end

    it('defaults to the cursor position of the current window', function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'abcdef' })
      local first_line = range(0, 0, 0, 5)

      vim.api.nvim_win_set_cursor(0, { 1, 2 })
      assert.is_true(lsp_utils.range_contains_cursor(first_line))

      vim.api.nvim_win_set_cursor(0, { 1, 5 })
      assert.is_true(lsp_utils.range_contains_cursor(first_line))
      assert.is_false(lsp_utils.range_contains_cursor(first_line, nil, true))
    end)
  end)
end)
