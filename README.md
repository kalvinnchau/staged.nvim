# staged.nvim

ephemeral comments for [codediff.nvim](https://github.com/esmuellert/codediff.nvim) diffs.

comments live on the modified side, track line positions, and disappear when the tab closes.

Working-tree, index, and commit-revision comments are separate, even for the same path.
Changing only the base revision retains the same comments.

## requirements

- neovim >= 0.12.5
- [codediff.nvim](https://github.com/esmuellert/codediff.nvim) >= 4.0.5, < 5.0.0
- optionally, a clipboard provider for clipboard exports (`:checkhealth provider`)

## install

```lua
-- lazy.nvim
{
  'kalvinnchau/staged.nvim',
  dependencies = { { 'esmuellert/codediff.nvim', version = '^4.0.5' } },
  opts = {},
}
```

## config

```lua
-- lazy.nvim
{
  'kalvinnchau/staged.nvim',
  dependencies = { { 'esmuellert/codediff.nvim', version = '^4.0.5' } },
  opts = {
    activation = {
      mode = 'auto', -- 'auto' or 'manual' session creation
    },
    keymaps = {
      prefix = '<leader>c', -- prefix for all keymaps
      add = 'i',            -- add/insert comment
      edit = 'e',           -- edit comment
      delete = 'd',         -- delete comment
      clear_all = 'D',      -- clear all comments
      undo = 'u',           -- undo comment change
      redo = 'r',           -- redo comment change
      toggle_sidebar = 's', -- toggle sidebar
      export_clipboard = 'y', -- export to clipboard
      export_buffer = 'b',  -- export to buffer
      export_file = 'w',    -- export to file
      next_comment = ']m',  -- jump to next (no prefix)
      prev_comment = '[m',  -- jump to prev (no prefix)
    },
    sidebar = {
      position = 'left', -- 'left' or 'right'
      width = 40,        -- sidebar width
      height = 15,       -- height when placed below codediff's explorer
      auto_show = true,  -- show on first comment
    },
    inline = {
      style = 'sign',                         -- 'sign', 'virtual_text', 'line_highlight'
      sign_icon = '>>',                       -- sign column icon
      priority = 150,                         -- indicator priority (0–65535)
      virtual_text_format = '[%d comment(s)]', -- string.format pattern
    },
    input = {
      style = 'floating', -- 'floating' or vim.ui.input-backed 'inline'
    },
    export = {
      include_code = true, -- include code snippets in export
      format = 'markdown',  -- 'markdown', 'plain', or 'json'
    },
  },
}
```

## keymaps

in codediff modified buffer:

- `<leader>ci` - add comment (visual mode for ranges)
- `<leader>ce` - edit
- `<leader>cd` - delete
- `<leader>cD` - clear all
- `<leader>cu` / `<leader>cr` - undo/redo comment changes
- `<leader>cs` - toggle sidebar
- `<leader>cy` - export to clipboard
- `<leader>cb` - export to buffer
- `<leader>cw` - export to file
- `]m` / `[m` - next/prev comment

in sidebar:

- `<CR>` - reopen the comparison and jump to the comment
- `e` - edit comment
- `d` - delete comment
- `q` - close sidebar

The floating input grows with wrapped/multiline content and stays within the editor viewport.

in the floating input window:

- `<C-s>` - save comment
- `<CR>` - save (normal mode)
- `<Esc>` - leave insert mode; cancel when already in normal mode
- `q` - cancel (normal mode)

## commands

- `:StagedAdd` - add comment at cursor
- `:StagedEdit` - edit comment at cursor
- `:StagedDelete` - delete comment at cursor
- `:StagedClear` - clear all comments
- `:StagedUndo` / `:StagedRedo` - undo/redo comment changes
- `:StagedToggle` - toggle sidebar
- `:StagedExport [clipboard|buffer|file] [markdown|plain|json]` - export comments
- `:StagedEnable` - enable for current codediff (manual mode)

## export

outputs markdown, plain text, or versioned JSON with optional code snippets:

```markdown
## path/to/file.lua

- **Line 10**: needs error handling
```

```json
{"comments":[{"end_line":10,"modified_revision":"WORKING","path":"lua/example.lua","side":"modified","start_line":10,"text":"needs error handling"}],"schema_version":2}
```

JSON schema 2 replaces schema 1, adding modified-side revision metadata. Paths are relative
to the codediff session root and omitted for files outside it. Positions and snippets survive
buffer unloads and reloads, including undo/redo anchors.

## explorer comment counts (opt-in)

Once both plugins are on the runtime path, add wrappers to **codediff's** setup options:

```lua
require('codediff').setup({
  -- Keep your other codediff options here.
  explorer = { formatters = require('staged.integration.explorer').formatters() },
})
```

File, folder, and group rows show `comments:N`, with revision-aware counts refreshed on
comment changes, undo/redo, and explorer redraws. Existing callbacks can be wrapped with
`formatters({ file = my_file_formatter, folder = my_folder_formatter, group = my_group_formatter })`.

Upstream row contexts lack a tab handle. Controlled redraws supply it; otherwise counts
are omitted unless the active buffer identifies the explorer. Advanced callers may supply
`tabpage` or `resolve_tabpage(ctx)`—never assume a background render belongs to the current tab.

## events

comment mutations emit `User` events:

- `StagedCommentAdded`
- `StagedCommentEdited`
- `StagedCommentDeleted`
- `StagedCommentsCleared`
- `StagedCommentsChanged` - emitted for every mutation, undo, and redo

Event data includes the tabpage, action, and total comment count. Comment events also include
`comment_id`, `file_path`, and a comment snapshot without internal extmark state.

## health and development

Run `:checkhealth staged` to check versions, configuration, codediff accessors/session,
and optional clipboard support.

Development uses [mise](https://mise.jdx.dev/) and
[plenary.nvim](https://github.com/nvim-lua/plenary.nvim), installed at `stdpath('data')/lazy/plenary.nvim`.

```bash
mise install
just fmt         # format Lua
just check       # lint + unit + real-codediff tests
just test        # unit tests only
just test-real   # real-codediff tests only
just lint        # formatting check only
```

The real suite needs codediff and its matching native library already installed at
`stdpath('data')/lazy/codediff.nvim`; it never downloads dependencies. That suite accepts
`STAGED_CODEDIFF_PATH` and `STAGED_PLENARY_PATH` overrides. Disposable fixtures live under
`.review/`; Git tests clone local HEAD and modify only fixture files/index, without commits.
This Lua project has no native build or sanitizer target.

```bash
mise x -- nvim -u config/with_codediff.lua  # isolated manual test; leader is comma
mise x -- nvim -u config/init.lua          # plugin-only sandbox
```

## license

MIT. See [LICENSE](LICENSE) for details.
