-- markdown-headings.nvim
-- Telescope heading picker and [/] heading navigation for Markdown files.
-- Supports both ATX (# ...) and Setext (=== / ---) headings.
-- Auto-detects which format the file uses and parses only that style.

local M = {}

--- Parse all headings from a buffer.
--- Returns a list of { lnum = int, level = int, text = string } in file order.
---@param bufnr? integer  buffer handle (default: current buffer)
---@return table[] headings
function M.parse(bufnr)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Build set of lines inside fenced code blocks
  local in_fence = {}
  local fence = false
  for i, line in ipairs(lines) do
    if line:match('^```') then fence = not fence end
    if fence then in_fence[i] = true end
  end

  -- Count ATX vs setext candidates (outside code blocks) to pick format
  local atx_n, setext_n = 0, 0
  for i, line in ipairs(lines) do
    if not in_fence[i] then
      if line:match('^#+%s+') then atx_n = atx_n + 1 end
      if i < #lines and not in_fence[i + 1] and line:match('%S') then
        local next_line = lines[i + 1]
        if next_line:match('^===+%s*$') or next_line:match('^%-%-%-+%s*$') then
          setext_n = setext_n + 1
        end
      end
    end
  end

  local headings = {}
  if setext_n >= atx_n then
    for i = 1, #lines - 1 do
      if not in_fence[i] and not in_fence[i + 1] and lines[i]:match('%S') then
        local next_line = lines[i + 1]
        if next_line:match('^===+%s*$') then
          headings[#headings + 1] = { lnum = i, level = 1, text = lines[i] }
        elseif next_line:match('^%-%-%-+%s*$') then
          headings[#headings + 1] = { lnum = i, level = 2, text = lines[i] }
        end
      end
    end
  else
    for i, line in ipairs(lines) do
      if not in_fence[i] then
        local hashes, text = line:match('^(#+)%s+(.*)')
        if hashes then
          headings[#headings + 1] = { lnum = i, level = #hashes, text = text }
        end
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
  local total_lines = vim.api.nvim_buf_line_count(0)
  local atx_pat = '^' .. string.rep('#', level) .. '%s'
  local setext_esc = (level == 1) and '=' or '%-'
  local setext_pat = '^' .. string.rep(setext_esc, 3) .. '+%s*$'

  -- Check if lnum is (part of) a heading at the target level.
  -- Returns the heading text line number, or nil.
  local function heading_line(lnum)
    if lnum < 1 or lnum > total_lines then return nil end
    local line = vim.fn.getline(lnum)
    -- ATX heading: exact level (## won't match ###)
    if line:match(atx_pat) then return lnum end
    -- Setext: underline line with non-blank text above
    if line:match(setext_pat) and lnum > 1
       and vim.fn.getline(lnum - 1):match('%S') then
      return lnum - 1
    end
    return nil
  end

  -- Determine the line range to skip (current heading block, if any).
  -- Handles cursor on ATX line, setext text line, or setext underline.
  local skip_lo, skip_hi = start_line, start_line
  if start_line < total_lines
     and vim.fn.getline(start_line + 1):match(setext_pat)
     and vim.fn.getline(start_line):match('%S') then
    skip_hi = start_line + 1       -- cursor on setext text line
  end
  if vim.fn.getline(start_line):match(setext_pat) and start_line > 1 then
    skip_lo = start_line - 1       -- cursor on setext underline
  end

  if direction == 'forward' then
    for lnum = skip_hi + 1, total_lines do
      local target = heading_line(lnum)
      if target then vim.fn.cursor(target, 1); return end
    end
  else
    for lnum = skip_lo - 1, 1, -1 do
      local target = heading_line(lnum)
      if target then vim.fn.cursor(target, 1); return end
    end
  end
end

--- Set up buffer-local keymaps for heading navigation.
--- Called automatically via FileType autocmd, or manually.
---@param opts? { jump_keys?: table<string,{direction:string,level:integer}> }
function M.setup(opts)
  opts = opts or {}

  local jump_keys = opts.jump_keys or {
    [']1'] = { direction = 'forward',  level = 1 },
    ['[1'] = { direction = 'backward', level = 1 },
    [']2'] = { direction = 'forward',  level = 2 },
    ['[2'] = { direction = 'backward', level = 2 },
  }

  local augroup = vim.api.nvim_create_augroup('MarkdownHeadings', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = augroup,
    pattern = 'markdown',
    callback = function()
      for key, mapping in pairs(jump_keys) do
        vim.keymap.set('n', key, function()
          M.jump(mapping.direction, mapping.level)
        end, { buffer = true, silent = true, desc = mapping.direction .. ' heading ' .. mapping.level })
      end
    end,
  })
end

return M
