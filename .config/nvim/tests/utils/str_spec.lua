local str = require('my.utils.str')

describe('[utils][str]', function()
  describe('detect_case', function()
    local cases = {
      { 'foo_bar_baz', 'snake' },
      { 'foo-bar-baz', 'lisp' },
      { 'fooBarBaz', 'camel' },
      { 'FooBarBaz', 'pascal' },
      { 'foo.bar.baz', 'dot' },
    }

    for _, case in ipairs(cases) do
      it(('detects %q as %s case'):format(case[1], case[2]), function()
        assert.are.same(case[2], str.detect_case(case[1]))
      end)
    end

    local ambiguous = {
      '', -- empty string has no case
      'foo', -- all lowercase, could be snake, lisp, dot, etc.
      'FOO', -- all uppercase, could be any case
      'foo_bar-baz', -- mixed separators
      'foo_bar.baz',
      'foo-bar.baz', -- luacheck: ignore 631
    }

    for _, input in ipairs(ambiguous) do
      it(('fails to detect the case of %q'):format(input), function()
        assert.is_nil(str.detect_case(input))
      end)
    end
  end)

  describe('case conversion', function()
    -- Converting to the case style a string is already in is a no-op, and
    -- strings with undetectable case styles are returned as is
    local cases = {
      {
        input = 'foo_bar_baz',
        snake = 'foo_bar_baz',
        lisp = 'foo-bar-baz',
        camel = 'fooBarBaz',
        pascal = 'FooBarBaz',
        dot = 'foo.bar.baz',
      },
      {
        input = 'foo-bar-baz',
        snake = 'foo_bar_baz',
        lisp = 'foo-bar-baz',
        camel = 'fooBarBaz',
        pascal = 'FooBarBaz',
        dot = 'foo.bar.baz',
      },
      {
        input = 'fooBarBaz',
        snake = 'foo_bar_baz',
        lisp = 'foo-bar-baz',
        camel = 'fooBarBaz',
        pascal = 'FooBarBaz',
        dot = 'foo.bar.baz',
      },
      {
        input = 'FooBarBaz',
        snake = 'foo_bar_baz',
        lisp = 'foo-bar-baz',
        camel = 'fooBarBaz',
        pascal = 'FooBarBaz',
        dot = 'foo.bar.baz',
      },
      {
        input = 'foo.bar.baz',
        snake = 'foo_bar_baz',
        lisp = 'foo-bar-baz',
        camel = 'fooBarBaz',
        pascal = 'FooBarBaz',
        dot = 'foo.bar.baz',
      },
      {
        input = 'foo',
        snake = 'foo',
        lisp = 'foo',
        camel = 'foo',
        pascal = 'foo',
        dot = 'foo',
      },
    }

    for _, case in ipairs(cases) do
      for _, target in ipairs({ 'snake', 'lisp', 'camel', 'pascal', 'dot' }) do
        it(('converts %q to %s case'):format(case.input, target), function()
          assert.are.same(case[target], str['to_' .. target](case.input))
        end)
      end
    end
  end)

  describe('escape_magic', function()
    it('escapes magic characters', function()
      assert.are.same(
        '%%%$%^%(%)%.%[%]%*%+%-%?',
        str.escape_magic('%$^().[]*+-?')
      )
    end)
    it('leaves non-magic characters alone', function()
      assert.are.same('foo_bar 123', str.escape_magic('foo_bar 123'))
    end)
    it('makes magic characters match literally', function()
      local escaped = str.escape_magic('a.b*c(d)')
      assert.is_truthy(('xa.b*c(d)y'):find(escaped))
      assert.is_nil(('xaXbYcZd)y'):find(escaped))
    end)
  end)
end)
