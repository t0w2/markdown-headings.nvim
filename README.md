# markdown-headings.nvim

Telescope heading picker, `]`/`[` heading navigation, and `gf` link
following for Markdown files.

- **Auto-detects format**: counts ATX (`#`) vs Setext (`===`/`---`) headings
  and parses only the dominant style — no mixed-format noise.
- **Skips fenced code blocks**: headings inside `` ``` `` blocks are ignored.
- **Telescope picker**: fuzzy-searchable heading list with indentation by
  level. Pre-selects the heading the cursor is currently inside.
- **Jump mappings**: `]1`/`[1` and `]2`/`[2` jump to next/previous heading
  at that level. Works with both ATX and Setext headings.
- **Link following**: `gf` follows `[text](path)` links — URLs open
  externally, `#anchors` jump to headings, file links open the file,
  and `path.md#heading` opens the file then jumps to the anchor.
  Falls back to normal `gf` outside of markdown links.

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

### Link following

After `setup()`, `gf` is overridden in Markdown buffers to follow
`[text](path)` links. The cursor can be anywhere inside the link syntax
(on the text or the path).

| Link type | Example | Action |
|---|---|---|
| URL | `[docs](https://example.com)` | Opens in external browser via `vim.ui.open()` |
| Internal anchor | `[see below](#installation)` | Jumps to the matching heading in the current buffer |
| File link | `[readme](other.md)` | Opens the file (relative to the current file's directory) |
| File + anchor | `[api](other.md#setup)` | Opens the file, then jumps to the heading |

Anchor matching uses GitHub-style slug conversion: lowercase, spaces to
hyphens, punctuation stripped. If the cursor is not inside a markdown link,
`gf` falls back to its default Neovim behavior.

To disable link following: `require('markdown-headings').setup({ follow_links = false })`

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

-- Jump to an anchor in the current buffer (GitHub-style slug matching)
mh.jump_to_anchor('installation')  -- returns true if found

-- Follow the markdown link under the cursor
mh.follow_link()                   -- handles URLs, anchors, files, file+anchor
```

## Format detection

The parser counts ATX (`# heading`) and Setext (underline `===`/`---`)
heading candidates outside fenced code blocks. Whichever style has more
occurrences wins — the other style is ignored entirely. Ties go to Setext.

This means a Setext-formatted file won't pick up stray `#` lines as
headings, and an ATX file won't treat `---` horizontal rules as H2.
