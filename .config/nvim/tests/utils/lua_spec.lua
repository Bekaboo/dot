local lua_utils = require('my.utils.lua')

describe('[utils][lua]', function()
  describe('nest', function()
    it('builds a nested table from a list of keys', function()
      assert.are.same({
        a = {
          b = {
            c = 'hello',
          },
        },
      }, lua_utils.nest({ 'a', 'b', 'c' }, 'hello'))
    end)
    it('returns the value itself for an empty list of keys', function()
      assert.are.same('hello', lua_utils.nest({}, 'hello'))
    end)
  end)

  describe('unnest', function()
    it('flattens nested tables with dot separated keys', function()
      assert.are.same(
        {
          ['a.b'] = 'hello',
          ['a.c'] = 'world',
        },
        lua_utils.unnest({
          a = {
            b = 'hello',
            c = 'world',
          },
        })
      )
    end)
    it('accepts a custom delimiter', function()
      assert.are.same(
        {
          ['a/b'] = 'hello',
        },
        lua_utils.unnest({
          a = {
            b = 'hello',
          },
        }, '/')
      )
    end)
    it('keeps lists as values instead of flattening them', function()
      assert.are.same(
        {
          ['a.b'] = { 'apple', 'orange' },
        },
        lua_utils.unnest({
          a = {
            b = { 'apple', 'orange' },
          },
        })
      )
    end)
    it('round trips with nest', function()
      assert.are.same({
        ['a.b.c'] = 'hello',
      }, lua_utils.unnest(lua_utils.nest({ 'a', 'b', 'c' }, 'hello')))
    end)
  end)

  describe('cache', function()
    it('only calls the function once for the same parameters', function()
      local calls = 0
      local cached = lua_utils.cache(function(a, b)
        calls = calls + 1
        return a + b
      end, {})

      assert.are.same(3, cached(1, 2))
      assert.are.same(3, cached(1, 2))
      assert.are.same(1, calls)

      assert.are.same(7, cached(3, 4))
      assert.are.same(2, calls)
    end)
    it('caches nil results', function()
      local calls = 0
      local cached = lua_utils.cache(function()
        calls = calls + 1
      end, {})

      assert.is_nil(cached())
      assert.is_nil(cached())
      assert.are.same(1, calls)
    end)
  end)

  describe('dedup', function()
    it('removes duplicate items from a list', function()
      local deduped = lua_utils.dedup({ 'a', 'b', 'a', 'c', 'b' })
      local set = {}
      for _, item in ipairs(deduped) do
        set[item] = true
      end
      assert.are.same({
        a = true,
        b = true,
        c = true,
      }, set)
      assert.are.same(3, #deduped)
    end)
    it('returns an empty list unchanged', function()
      assert.are.same({}, lua_utils.dedup({}))
    end)
  end)
end)
