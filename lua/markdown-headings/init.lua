-- markdown-headings.nvim
-- Telescope heading picker, [/] heading navigation, and gf link following
-- for Markdown files.
-- Supports mixed ATX (# ...) and Setext (=== / ---) headings.

local M = {}

local function trim(text)
  return (text:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function parse_atx(line)
  local indent, rest = line:match('^( *)(.*)$')
  if #indent > 3 then return nil end

  local hashes = rest:match('^(#+)')
  if not hashes or #hashes > 6 then return nil end

  local text = rest:sub(#hashes + 1)
  if text ~= '' and not text:match('^[ \t]') then return nil end

  text = trim(text):gsub('[ \t]+#+[ \t]*$', '')
  return #hashes, trim(text)
end

local function setext_level(line)
  local indent, rest = line:match('^( *)(.*)$')
  if #indent > 3 then return nil end

  rest = trim(rest)
  if rest:match('^=+$') then return 1 end
  if rest:match('^%-+$') then return 2 end
  return nil
end

local function fence_start(line)
  local indent, rest = line:match('^( *)(.*)$')
  if #indent > 3 then return nil end

  local ticks = rest:match('^(```+)')
  if ticks then return '`', #ticks end

  local tildes = rest:match('^(~~~+)')
  if tildes then return '~', #tildes end

  return nil
end

local function fence_closes(line, fence_char, fence_len)
  local indent, rest = line:match('^( *)(.*)$')
  if #indent > 3 then return false end

  local chars
  if fence_char == '`' then
    chars = rest:match('^(`+)%s*$')
  else
    chars = rest:match('^(~+)%s*$')
  end

  return chars and #chars >= fence_len
end

local function fenced_lines(lines)
  local in_fence = {}
  local fence_char, fence_len

  for i, line in ipairs(lines) do
    if fence_char then
      in_fence[i] = true
      if fence_closes(line, fence_char, fence_len) then
        fence_char, fence_len = nil, nil
      end
    else
      local char, len = fence_start(line)
      if char then
        in_fence[i] = true
        fence_char, fence_len = char, len
      end
    end
  end

  return in_fence
end

local function slugify(text)
  return text:lower()
    :gsub('[^%w%s-]', '')
    :gsub('%s+', '-')
    :gsub('^-+', '')
    :gsub('-+$', '')
end

local function percent_decode(text)
  return (text:gsub('%%(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

local function normalize_anchor(anchor)
  return slugify(percent_decode(anchor:gsub('^#', '')))
end

local default_jump_keys = {
  [']1'] = { direction = 'forward',  level = 1 },
  ['[1'] = { direction = 'backward', level = 1 },
  [']2'] = { direction = 'forward',  level = 2 },
  ['[2'] = { direction = 'backward', level = 2 },
}

local config = {
  jump_keys = default_jump_keys,
  follow_links = true,
  style = 'mixed',
}

local attached_keys = {}

local function mark_front_matter(lines, ignored)
  if not lines[1] or not lines[1]:match('^%-%-%-%s*$') then return end

  for i = 2, #lines do
    if lines[i]:match('^%-%-%-%s*$') or lines[i]:match('^%.%.%.%s*$') then
      for lnum = 1, i do
        ignored[lnum] = true
      end
      return
    end
  end
end

--- Parse all headings from a buffer.
--- Returns a list of { lnum = int, end_lnum = int, level = int, text = string } in file order.
---@param bufnr? integer  buffer handle (default: current buffer)
---@param opts? { style?: "mixed"|"auto"|"atx"|"setext" }
---@return table[] headings
function M.parse(bufnr, opts)
  if type(bufnr) == 'table' then
    opts = bufnr
    bufnr = 0
  end

  bufnr = bufnr or 0
  opts = opts or {}
  local style = opts.style or config.style
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Build set of lines inside fenced code blocks
  local ignored = fenced_lines(lines)
  mark_front_matter(lines, ignored)

  local function setext_candidate(i)
    if i >= #lines or ignored[i] or ignored[i + 1] or not lines[i]:match('%S') then return nil end
    if parse_atx(lines[i]) then return nil end
    return setext_level(lines[i + 1])
  end

  -- Count ATX vs setext candidates (outside ignored regions) to pick format
  if style == 'auto' then
    local atx_n, setext_n = 0, 0
    for i, line in ipairs(lines) do
      if not ignored[i] then
        if parse_atx(line) then atx_n = atx_n + 1 end
        if setext_candidate(i) then setext_n = setext_n + 1 end
      end
    end
    style = (setext_n >= atx_n) and 'setext' or 'atx'
  end

  if style ~= 'atx' and style ~= 'setext' and style ~= 'mixed' then
    style = 'mixed'
  end

  local headings = {}
  for i, line in ipairs(lines) do
    if not ignored[i] then
      local atx_level, text = parse_atx(line)
      if atx_level and (style == 'atx' or style == 'mixed') then
        headings[#headings + 1] = { lnum = i, end_lnum = i, level = atx_level, text = text }
      end

      local setext = setext_candidate(i)
      if setext and (style == 'setext' or style == 'mixed') then
        headings[#headings + 1] = { lnum = i, end_lnum = i + 1, level = setext, text = trim(line) }
      end
    end
  end

  return headings
end

--- Open a Telescope picker listing all headings in the current buffer.
--- Pre-selects the heading the cursor is currently inside.
function M.picker()
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values

  local headings = M.parse()
  if #headings == 0 then
    vim.notify('No headings found', vim.log.levels.INFO)
    return
  end

  -- Pre-select the heading the cursor is currently inside
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local sel = 1
  for i, h in ipairs(headings) do
    if h.lnum <= cursor_line then sel = i end
  end

  local fname = vim.api.nvim_buf_get_name(0)
  pickers.new({}, {
    prompt_title = 'Headings',
    sorting_strategy = 'ascending',
    default_selection_index = sel,
    finder = finders.new_table({
      results = headings,
      entry_maker = function(e)
        return { value = e, ordinal = e.text, lnum = e.lnum, filename = fname,
                 display = string.rep('  ', e.level - 1) .. e.text }
      end,
    }),
    sorter = conf.generic_sorter({}),
    previewer = conf.grep_previewer({}),
  }):find()
end

--- Jump to the next or previous heading at the given level.
--- Supports ATX and Setext headings. Skips the current heading.
---@param direction "forward"|"backward"
---@param level integer  heading level (1 or 2 for setext, 1-6 for ATX)
function M.jump(direction, level)
  local start_line = vim.fn.line('.')
  local headings = M.parse()

  if direction == 'forward' then
    for _, h in ipairs(headings) do
      if h.level == level and h.lnum > start_line then
        vim.fn.cursor(h.lnum, 1)
        return
      end
    end
  else
    for i = #headings, 1, -1 do
      local h = headings[i]
      if h.level == level and (h.end_lnum or h.lnum) < start_line then
        vim.fn.cursor(h.lnum, 1)
        return
      end
    end
  end
end

--- Jump to a #heading anchor in the current buffer.
--- Converts heading text to a GitHub-style slug (lowercase, spaces to hyphens,
--- strip punctuation) and searches for the first matching heading.
--- Uses M.parse() so both ATX and Setext headings are found.
---@param anchor string  anchor with or without leading '#'
---@return boolean  true if the heading was found
function M.jump_to_anchor(anchor)
  local target = normalize_anchor(anchor)
  local seen = {}

  for _, h in ipairs(M.parse()) do
    local base = slugify(h.text)
    local count = seen[base] or 0
    local slug = count == 0 and base or (base .. '-' .. count)
    seen[base] = count + 1

    if slug == target then
      vim.api.nvim_win_set_cursor(0, { h.lnum, 0 })
      return true
    end
  end

  vim.notify('Heading not found: #' .. target, vim.log.levels.WARN)
  return false
end

local function matching_bracket(line, open)
  local depth = 1
  local i = open + 1

  while i <= #line do
    local ch = line:sub(i, i)
    if ch == '\\' then
      i = i + 2
    elseif ch == '[' then
      depth = depth + 1
      i = i + 1
    elseif ch == ']' then
      depth = depth - 1
      if depth == 0 then return i end
      i = i + 1
    else
      i = i + 1
    end
  end

  return nil
end

local function closing_paren_after_title(line, start)
  local i = start
  while line:sub(i, i):match('%s') do i = i + 1 end
  if line:sub(i, i) == ')' then return i end

  local quote = line:sub(i, i)
  if quote == '"' or quote == "'" then
    i = i + 1
    while i <= #line do
      local ch = line:sub(i, i)
      if ch == '\\' then
        i = i + 2
      elseif ch == quote then
        i = i + 1
        break
      else
        i = i + 1
      end
    end
  elseif quote == '(' then
    local depth = 1
    i = i + 1
    while i <= #line do
      local ch = line:sub(i, i)
      if ch == '\\' then
        i = i + 2
      elseif ch == '(' then
        depth = depth + 1
        i = i + 1
      elseif ch == ')' then
        depth = depth - 1
        i = i + 1
        if depth == 0 then break end
      else
        i = i + 1
      end
    end
  else
    return nil
  end

  while line:sub(i, i):match('%s') do i = i + 1 end
  if line:sub(i, i) == ')' then return i end
  return nil
end

local function parse_link_destination(line, start)
  local i = start
  while line:sub(i, i):match('%s') do i = i + 1 end

  if line:sub(i, i) == '<' then
    local close = line:find('>', i + 1, true)
    if not close then return nil end

    local finish = closing_paren_after_title(line, close + 1)
    if not finish then return nil end
    return line:sub(i + 1, close - 1), finish
  end

  local depth = 0
  local j = i
  while j <= #line do
    local ch = line:sub(j, j)
    if ch == '\\' then
      j = j + 2
    elseif ch == '(' then
      depth = depth + 1
      j = j + 1
    elseif ch == ')' then
      if depth == 0 then
        return trim(line:sub(i, j - 1)), j
      end
      depth = depth - 1
      j = j + 1
    elseif ch:match('%s') and depth == 0 then
      local finish = closing_paren_after_title(line, j)
      if not finish then return nil end
      return trim(line:sub(i, j - 1)), finish
    else
      j = j + 1
    end
  end

  return nil
end

local function link_at_cursor(line, col)
  local i = 1
  while i <= #line do
    local open = line:find('[', i, true)
    if not open then return nil end

    local close = matching_bracket(line, open)
    if close and line:sub(close + 1, close + 1) == '(' then
      local path, finish = parse_link_destination(line, close + 2)
      if path and col >= open and col <= finish then
        return path
      end
      i = (finish or close) + 1
    else
      i = open + 1
    end
  end

  return nil
end

local function edit_file(path)
  local file = percent_decode(path)
  if not file:match('^/') and not file:match('^~[/\\]') then
    file = vim.fn.expand('%:p:h') .. '/' .. file
  end
  vim.cmd('edit ' .. vim.fn.fnameescape(vim.fn.expand(file)))
end

--- Follow the markdown link under or around the cursor.
--- Handles URLs (opens externally), internal anchors (#heading), file links,
--- and combined file+anchor links (path.md#heading).
--- Falls back to normal gf if the cursor is not inside a [text](path) link.
function M.follow_link()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local path = link_at_cursor(line, col)

  if not path then
    vim.cmd('normal! gf')
    return
  end

  if path:match('^[%a][%w+.-]*:') then
    vim.ui.open(path)
    return
  end

  local file, anchor = path:match('^(.-)(#.*)$')
  if file == nil then
    file = path
  end

  if file == '' and anchor then
    M.jump_to_anchor(anchor)
    return
  end

  edit_file(file)
  if anchor and anchor ~= '#' then M.jump_to_anchor(anchor) end
end

local function attach(bufnr)
  for key in pairs(attached_keys[bufnr] or {}) do
    pcall(vim.keymap.del, 'n', key, { buffer = bufnr })
  end

  attached_keys[bufnr] = {}
  for key, mapping in pairs(config.jump_keys) do
    local direction, target_level = mapping.direction, mapping.level
    vim.keymap.set('n', key, function()
      M.jump(direction, target_level)
    end, { buffer = bufnr, silent = true, desc = direction .. ' heading ' .. target_level })
    attached_keys[bufnr][key] = true
  end

  if config.follow_links then
    vim.keymap.set('n', 'gf', M.follow_link,
      { buffer = bufnr, silent = true, desc = 'Follow markdown link' })
    attached_keys[bufnr].gf = true
  end
end

--- Set up buffer-local keymaps for heading navigation and link following.
--- Called automatically via FileType autocmd, or manually.
---@param opts? { jump_keys?: table<string,{direction:string,level:integer}>, follow_links?: boolean, style?: "mixed"|"auto"|"atx"|"setext" }
function M.setup(opts)
  opts = opts or {}
  config.jump_keys = opts.jump_keys or default_jump_keys
  config.follow_links = opts.follow_links ~= false
  config.style = opts.style or 'mixed'

  local augroup = vim.api.nvim_create_augroup('MarkdownHeadings', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = augroup,
    pattern = 'markdown',
    callback = function(args)
      attach(args.buf)
    end,
  })

  local current = vim.api.nvim_get_current_buf()
  if vim.bo[current].filetype == 'markdown' then
    attach(current)
  end
end

return M
