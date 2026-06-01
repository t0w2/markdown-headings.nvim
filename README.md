# markdown-headings.nvim

Telescope heading picker and `]`/`[` heading navigation for Markdown files.

- **Auto-detects format**: counts ATX (`#`) vs Setext (`===`/`---`) headings
  and parses only the dominant style — no mixed-format noise.
- **Skips fenced code blocks**: headings inside `` ``` `` blocks are ignored.
- **Telescope picker**: fuzzy-searchable heading list with indentation by
  level. Pre-selects the heading the cursor is currently inside.
- **Jump mappings**: `]1`/`[1` and `]2`/`[2` jump to next/previous heading
  at that level. Works with both ATX and Setext headings.

## Installation

### lazy.nvim

```lua
{
  't0w2/markdown-headings.nvim',
  dependencies = { 'nvim-telescope/telescope.nvim' },
  ft = 'markdown',
  keys = {
    { '<F8>', function()
        require('markdown-headings').picker()
      end, ft = 'markdown', desc = 'Markdown headings' },
  },
  config = function()
    require('markdown-headings').setup()
  end,
}
```

## Usage

### Telescope picker

```lua
require('markdown-headings').picker()
```

Opens a Telescope picker listing all headings in the current buffer.
Headings are displayed in file order with indentation showing hierarchy.
The cursor starts on the heading you're currently inside.

### Heading navigation

After `setup()`, these buffer-local mappings are active in Markdown files:

| Key  | Action                    |
|------|---------------------------|
| `]1` | Next level-1 heading      |
| `[1` | Previous level-1 heading  |
| `]2` | Next level-2 heading      |
| `[2` | Previous level-2 heading  |

### Custom jump keys

```lua
require('markdown-headings').setup({
  jump_keys = {
    [']1'] = { direction = 'forward',  level = 1 },
    ['[1'] = { direction = 'backward', level = 1 },
    [']2'] = { direction = 'forward',  level = 2 },
    ['[2'] = { direction = 'backward', level = 2 },
    [']3'] = { direction = 'forward',  level = 3 },
    ['[3'] = { direction = 'backward', level = 3 },
  },
})
```

### API

```lua
local mh = require('markdown-headings')

-- Parse headings from current buffer (or specify bufnr)
local headings = mh.parse()        -- returns { { lnum, level, text }, ... }

-- Jump programmatically
mh.jump('forward', 1)              -- next H1
mh.jump('backward', 2)             -- previous H2
```

## Format detection

The parser counts ATX (`# heading`) and Setext (underline `===`/`---`)
heading candidates outside fenced code blocks. Whichever style has more
occurrences wins — the other style is ignored entirely. Ties go to Setext.

This means a Setext-formatted file won't pick up stray `#` lines as
headings, and an ATX file won't treat `---` horizontal rules as H2.
