local fs_utils = require('my.utils.fs')

describe('[utils][fs]', function()
  local dir = nil ---@type string

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
  end)

  after_each(function()
    vim.fn.delete(dir, 'rf')
  end)

  ---Create a file with the given content under the test directory
  ---@param name string
  ---@param content string
  ---@return string path
  local function create_file(name, content)
    local path = vim.fs.joinpath(dir, name)
    vim.fn.mkdir(vim.fs.dirname(path), 'p')
    local file = assert(io.open(path, 'w'))
    file:write(content)
    file:close()
    return path
  end

  describe('read_file', function()
    it('reads file contents', function()
      local path = create_file('foo.txt', 'hello')
      assert.are.same('hello', fs_utils.read_file(path))
    end)
    it('returns nil for a nonexistent file', function()
      assert.is_nil(fs_utils.read_file(vim.fs.joinpath(dir, 'nope.txt')))
    end)
  end)

  describe('write_file', function()
    it('writes file contents', function()
      local path = vim.fs.joinpath(dir, 'foo.txt')
      assert.is_true(fs_utils.write_file(path, 'hello'))
      assert.are.same({ 'hello' }, vim.fn.readfile(path))
    end)
    it('round trips with read_file', function()
      local path = vim.fs.joinpath(dir, 'foo.txt')
      fs_utils.write_file(path, 'hello\nworld')
      assert.are.same('hello\nworld', fs_utils.read_file(path))
    end)
  end)

  describe('is_empty', function()
    it('is true for a nonexistent path', function()
      assert.is_true(fs_utils.is_empty(vim.fs.joinpath(dir, 'nope.txt')))
    end)
    it('is true for an empty file', function()
      assert.is_true(fs_utils.is_empty(create_file('empty.txt', '')))
    end)
    it('is false for a non-empty file', function()
      assert.is_false(fs_utils.is_empty(create_file('foo.txt', 'hello')))
    end)
  end)

  describe('diff', function()
    it('returns the file name when it distinguishes the paths', function()
      assert.are.same(
        { 'c', 'd', 'f' },
        fs_utils.diff({ 'a/b/c', 'a/b/d', 'a/e/f' })
      )
    end)
    it('returns as much of the path as needed to distinguish them', function()
      assert.are.same(
        { 'a/b', 'd/b', 'e' },
        fs_utils.diff({ 'a/b/c', 'd/b/c', 'e/c' })
      )
    end)
  end)

  describe('contains', function()
    it('is true for a file inside the directory', function()
      local parent = vim.fs.joinpath(dir, 'foo')
      local path = vim.fs.joinpath(parent, 'bar.txt')
      create_file('foo/bar.txt', 'hello')
      assert.is_true(fs_utils.contains(parent, path))
    end)
    it('is false for a sibling directory with the same prefix', function()
      local parent = vim.fs.joinpath(dir, 'foo')
      local path = vim.fs.joinpath(dir, 'foo-bar', 'bar.txt')
      vim.fn.mkdir(parent, 'p')
      create_file('foo-bar/bar.txt', 'hello')
      assert.is_false(fs_utils.contains(parent, path))
    end)
    it('is true for the directory itself unless strict', function()
      assert.is_true(fs_utils.contains(dir, dir))
      assert.is_false(fs_utils.contains(dir, dir, true))
    end)
  end)

  describe('is_root_dir', function()
    it('is true for the root directory', function()
      assert.is_true(fs_utils.is_root_dir('/'))
    end)
    it('is false for other directories', function()
      assert.is_false(fs_utils.is_root_dir(dir))
    end)
  end)

  describe('is_home_dir', function()
    it('is true for the home directory', function()
      assert.is_true(fs_utils.is_home_dir(vim.uv.os_homedir()))
    end)
    it('is false for other directories', function()
      assert.is_false(fs_utils.is_home_dir(dir))
    end)
  end)

  describe('is_full_path', function()
    it('is true for an absolute path', function()
      assert.is_true(fs_utils.is_full_path(dir))
    end)
    it('is false for a relative path', function()
      assert.is_false(fs_utils.is_full_path('foo/bar'))
      assert.is_false(fs_utils.is_full_path('./foo/bar'))
    end)
  end)

  describe('root', function()
    it('finds the nearest directory containing a root marker', function()
      local file = create_file('project/sub/file.txt', 'hello')
      create_file('project/.git/config', '')
      assert.are.same(
        vim.fs.joinpath(dir, 'project'),
        fs_utils.root(file, { '.git' })
      )
    end)
    it('prefers a marker set over the string markers after it', function()
      local file = create_file('outer/inner/file.txt', 'hello')
      create_file('outer/.git/config', '')
      create_file('outer/inner/.project', '')
      assert.are.same(
        vim.fs.joinpath(dir, 'outer/inner'),
        fs_utils.root(file, { { '.project' }, '.git' })
      )
    end)
    it(
      'searches the string markers after a marker set that does not match',
      function()
        local file = create_file('project/sub/file.txt', 'hello')
        create_file('project/.git/config', '')
        assert.are.same(
          vim.fs.joinpath(dir, 'project'),
          fs_utils.root(file, { { '.project' }, '.git' })
        )
      end
    )
    it('accepts a single root marker', function()
      local file = create_file('project/sub/file.txt', 'hello')
      create_file('project/.git/config', '')
      assert.are.same(
        vim.fs.joinpath(dir, 'project'),
        fs_utils.root(file, '.git')
      )
    end)
    it('honors the priority of layered root markers', function()
      local file = create_file('outer/inner/file.txt', 'hello')
      create_file('outer/.git/config', '')
      create_file('outer/inner/.project', '')
      -- The `.project` marker takes priority over `.git` even though it is
      -- found further away from the file
      assert.are.same(
        vim.fs.joinpath(dir, 'outer/inner'),
        fs_utils.root(file, { { '.project' }, { '.git' } })
      )
    end)
  end)
end)
