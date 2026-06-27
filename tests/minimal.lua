local repo = vim.fn.getcwd()
vim.opt.runtimepath:prepend(repo)
package.path = repo .. '/lua/?.lua;' .. repo .. '/lua/?/init.lua;' .. package.path

local mh = require('markdown-headings')
local tests = {}

local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function fail(message)
  error(message, 2)
end

local function assert_eq(actual, expected, message)
  if not vim.deep_equal(actual, expected) then
    fail((message or 'values differ') .. ': expected ' .. vim.inspect(expected) .. ', got ' .. vim.inspect(actual))
  end
end

local function assert_true(value, message)
  if not value then
    fail(message or 'expected truthy value')
  end
end

local function assert_false(value, message)
  if value then
    fail(message or 'expected falsy value')
  end
end

local function with_buffer(lines, fn, opts)
  opts = opts or {}
  local original = vim.api.nvim_get_current_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  if opts.name then
    vim.api.nvim_buf_set_name(buf, opts.name)
  end
  vim.bo[buf].filetype = 'markdown'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  local ok, err = xpcall(function()
    fn(buf)
  end, debug.traceback)

  if vim.api.nvim_buf_is_valid(original) then
    vim.api.nvim_set_current_buf(original)
  end
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end

  if not ok then
    error(err, 0)
  end
end

local function parsed_summary(headings)
  local summary = {}
  for _, heading in ipairs(headings) do
    summary[#summary + 1] = { heading.lnum, heading.level, heading.text }
  end
  return summary
end

test('parse ignores headings inside indented tilde fences', function()
  with_buffer({
    '# Visible',
    '   ~~~lua',
    '# Hidden',
    '   ~~~',
    '## Also visible',
  }, function(buf)
    assert_eq(parsed_summary(mh.parse(buf)), {
      { 1, 1, 'Visible' },
      { 5, 2, 'Also visible' },
    })
  end)
end)

test('parse normalizes ATX headings and rejects seven-hash headings', function()
  with_buffer({
    '# Title #',
    '## Section ###',
    '####### Not a heading',
  }, function(buf)
    assert_eq(parsed_summary(mh.parse(buf)), {
      { 1, 1, 'Title' },
      { 2, 2, 'Section' },
    })
  end)
end)

test('jump does not enter fenced code blocks', function()
  with_buffer({
    '# First',
    '```',
    '# Hidden',
    '```',
    '# Second',
  }, function()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    mh.jump('forward', 1)
    assert_eq(vim.api.nvim_win_get_cursor(0)[1], 5)
  end)
end)

test('jump_to_anchor matches duplicate GitHub-style slugs', function()
  with_buffer({
    '# API',
    '# API',
  }, function()
    assert_true(mh.jump_to_anchor('api-1'))
    assert_eq(vim.api.nvim_win_get_cursor(0)[1], 2)
  end)
end)

test('jump_to_anchor ignores ATX closing hashes', function()
  with_buffer({
    '# Install Guide #',
  }, function()
    assert_true(mh.jump_to_anchor('#install-guide'))
    assert_eq(vim.api.nvim_win_get_cursor(0)[1], 1)
  end)
end)

test('parse includes mixed ATX and Setext headings by default', function()
  with_buffer({
    'Title',
    '=====',
    '# Install',
    'Details',
    '---',
    '## API',
  }, function(buf)
    assert_eq(parsed_summary(mh.parse(buf)), {
      { 1, 1, 'Title' },
      { 3, 1, 'Install' },
      { 4, 2, 'Details' },
      { 6, 2, 'API' },
    })
  end)
end)

test('parse skips YAML front matter', function()
  with_buffer({
    '---',
    'title: Doc',
    '---',
    '# Real',
  }, function(buf)
    assert_eq(parsed_summary(mh.parse(buf)), {
      { 4, 1, 'Real' },
    })
  end)
end)

test('setup attaches mappings to the current markdown buffer', function()
  with_buffer({ '# Title' }, function(buf)
    mh.setup()
    local maps = vim.api.nvim_buf_get_keymap(buf, 'n')
    local found_gf, found_next = false, false
    for _, map in ipairs(maps) do
      if map.lhs == 'gf' then found_gf = true end
      if map.lhs == ']1' then found_next = true end
    end
    assert_true(found_gf, 'expected gf mapping')
    assert_true(found_next, 'expected ]1 mapping')
  end)
end)

test('follow_link handles balanced parentheses in destinations', function()
  with_buffer({ '[paren](foo(bar).md)' }, function()
    vim.api.nvim_win_set_cursor(0, { 1, 10 })
    mh.follow_link()
    assert_true(vim.api.nvim_buf_get_name(0):match('foo%(bar%).md$'), 'expected foo(bar).md buffer')
  end, { name = '/tmp/current.md' })
end)

test('follow_link handles angle destinations with spaces', function()
  with_buffer({ '[angle](<foo bar.md>)' }, function()
    vim.api.nvim_win_set_cursor(0, { 1, 10 })
    mh.follow_link()
    assert_true(vim.api.nvim_buf_get_name(0):match('foo bar%.md$'), 'expected foo bar.md buffer')
  end, { name = '/tmp/current.md' })
end)

test('follow_link strips optional link titles', function()
  with_buffer({ '[title](foo.md "Title")' }, function()
    vim.api.nvim_win_set_cursor(0, { 1, 10 })
    mh.follow_link()
    assert_true(vim.api.nvim_buf_get_name(0):match('foo%.md$'), 'expected foo.md buffer')
  end, { name = '/tmp/current.md' })
end)

test('follow_link preserves absolute paths', function()
  with_buffer({ '[abs](/tmp/absolute-target.md)' }, function()
    vim.api.nvim_win_set_cursor(0, { 1, 10 })
    mh.follow_link()
    assert_eq(vim.api.nvim_buf_get_name(0), '/tmp/absolute-target.md')
  end, { name = '/tmp/current.md' })
end)

test('parse style modes filter headings', function()
  with_buffer({
    'Title',
    '=====',
    '# Install',
    'Details',
    '---',
    '## API',
  }, function(buf)
    assert_eq(parsed_summary(mh.parse(buf, { style = 'atx' })), {
      { 3, 1, 'Install' },
      { 6, 2, 'API' },
    })
    assert_eq(parsed_summary(mh.parse(buf, { style = 'setext' })), {
      { 1, 1, 'Title' },
      { 4, 2, 'Details' },
    })
    assert_eq(parsed_summary(mh.parse(buf, { style = 'auto' })), {
      { 1, 1, 'Title' },
      { 4, 2, 'Details' },
    })
  end)
end)

test('parse respects longer backtick fence delimiters', function()
  with_buffer({
    '# Visible',
    '````markdown',
    '```',
    '# Hidden',
    '````',
    '# Also visible',
  }, function(buf)
    assert_eq(parsed_summary(mh.parse(buf)), {
      { 1, 1, 'Visible' },
      { 6, 1, 'Also visible' },
    })
  end)
end)

test('jump backward skips current Setext heading underline', function()
  with_buffer({
    '# First',
    'Middle',
    '---',
    '# Last',
  }, function()
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    mh.jump('backward', 1)
    assert_eq(vim.api.nvim_win_get_cursor(0)[1], 1)
  end)
end)

test('jump forward from Setext text skips current Setext heading', function()
  with_buffer({
    'First',
    '---',
    'Second',
    '---',
  }, function()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    mh.jump('forward', 2)
    assert_eq(vim.api.nvim_win_get_cursor(0)[1], 3)
  end)
end)

test('setup respects disabled link following', function()
  with_buffer({ '# Title' }, function(buf)
    mh.setup({ follow_links = false })
    local maps = vim.api.nvim_buf_get_keymap(buf, 'n')
    local found_gf, found_next = false, false
    for _, map in ipairs(maps) do
      if map.lhs == 'gf' then found_gf = true end
      if map.lhs == ']1' then found_next = true end
    end
    assert_false(found_gf, 'expected gf not to be mapped')
    assert_true(found_next, 'expected ]1 mapping')
  end)
end)

test('setup supports custom jump keys', function()
  with_buffer({ '# Title' }, function(buf)
    mh.setup({ jump_keys = { [']3'] = { direction = 'forward', level = 3 } } })
    local maps = vim.api.nvim_buf_get_keymap(buf, 'n')
    local found_next_1, found_next_3 = false, false
    for _, map in ipairs(maps) do
      if map.lhs == ']1' then found_next_1 = true end
      if map.lhs == ']3' then found_next_3 = true end
    end
    assert_false(found_next_1, 'expected default ]1 mapping to be replaced')
    assert_true(found_next_3, 'expected custom ]3 mapping')
  end)
end)

test('follow_link opens external URI schemes', function()
  local opened
  local original_open = vim.ui.open
  vim.ui.open = function(uri)
    opened = uri
  end

  local ok, err = pcall(function()
    with_buffer({ '[mail](mailto:a@example.com)' }, function()
      vim.api.nvim_win_set_cursor(0, { 1, 10 })
      mh.follow_link()
      assert_eq(opened, 'mailto:a@example.com')
    end, { name = '/tmp/current.md' })
  end)

  vim.ui.open = original_open
  if not ok then error(err, 0) end
end)

test('follow_link decodes file paths and jumps to decoded anchors', function()
  local target = '/tmp/target file.md'
  vim.fn.writefile({ '# My Heading' }, target)

  local ok, err = pcall(function()
    with_buffer({ '[encoded](target%20file.md#my%20heading)' }, function()
      vim.api.nvim_win_set_cursor(0, { 1, 12 })
      mh.follow_link()
      assert_true(vim.api.nvim_buf_get_name(0):match('target file%.md$'), 'expected decoded file name')
      assert_eq(vim.api.nvim_win_get_cursor(0)[1], 1)
    end, { name = '/tmp/current.md' })
  end)

  vim.fn.delete(target)
  if not ok then error(err, 0) end
end)

test('follow_link works when cursor is on closing parenthesis', function()
  with_buffer({ '[close](close.md)' }, function()
    vim.api.nvim_win_set_cursor(0, { 1, 15 })
    mh.follow_link()
    assert_true(vim.api.nvim_buf_get_name(0):match('close%.md$'), 'expected close.md buffer')
  end, { name = '/tmp/current.md' })
end)

local failures = {}
for _, item in ipairs(tests) do
  local ok, err = xpcall(item.fn, debug.traceback)
  if ok then
    print('PASS ' .. item.name)
  else
    failures[#failures + 1] = { name = item.name, err = err }
    print('FAIL ' .. item.name)
    print(err)
  end
end

if #failures > 0 then
  print(('%d/%d tests failed'):format(#failures, #tests))
  os.exit(1)
end

print(('PASS %d tests'):format(#tests))
