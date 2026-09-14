# staged.nvim

[Version](VERSION) · [Changelog](CHANGELOG.md)

Ephemeral review comments for [codediff.nvim](https://github.com/esmuellert/codediff.nvim).
Comments attach to modified-side lines, follow edits, and disappear when the codediff
session closes or Neovim exits—including `:restart`.

## requirements

- Neovim >= 0.12.5
- codediff.nvim >= 4.0.5, < 5.0.0
- Optional clipboard provider for clipboard exports (`:checkhealth provider`)

## install

```lua
-- lazy.nvim
{
  'kalvinnchau/staged.nvim',
  dependencies = { { 'esmuellert/codediff.nvim', version = '^4.0.5' } },
  opts = {},
}
```

For a local checkout or worktree, add `dir = '/absolute/path/to/staged.nvim'` to the spec.

## quick start

1. Open `:CodeDiff` and focus the modified pane.
2. Run `:StagedAdd`, type a comment, then press `<Esc><CR>` to save.
3. Use `<leader>ci` in Visual mode to comment on a line range.
4. Press `<CR>` on a sidebar comment to reopen its comparison and jump to its line.
5. Run `:StagedExport buffer json` to inspect the review.

The sidebar opens on the first comment, below a compatible left explorer/history panel
or in its own side split. Overlapping comments open a picker for edit/delete.
Comment undo/redo is separate from Neovim's text undo.

## config

Set these in lazy.nvim's `opts`, or pass them to `require('staged').setup()`:

```lua
{
  activation = { mode = 'auto' }, -- 'manual' requires :StagedEnable in each diff tab
  keymaps = { prefix = '<leader>c' },
  sidebar = {
    position = 'left', -- 'left' or 'right'
    width = 40,
    height = 15, -- when nested below a panel
    auto_show = true,
  },
  inline = {
    style = 'sign', -- 'sign', 'virtual_text', or 'line_highlight'
    sign_icon = '>>',
    priority = 150, -- 0–65535
    virtual_text_format = '[%d comment(s)]',
  },
  input = { style = 'floating' }, -- 'inline' delegates to vim.ui.input
  export = { include_code = true, format = 'markdown' }, -- 'markdown', 'plain', or 'json'
}
```

All defaults and individual keymap options: [config.lua](lua/staged/config.lua).

### sign visibility

`>>` marks saved comments, not every changed line. With `signcolumn=yes`, only one sign
fits per line; another sign can hide it. Use `signcolumn=auto:2` for extra space as needed,
or `inline.style = 'virtual_text'` to keep comments out of the gutter entirely.
Priority 150 sits above codediff's default change signs (100) and below moved-block signs (250).

## commands and keymaps

Default keys in the modified buffer; `<leader>` is your configured leader:

| Action | Key | Command |
| --- | --- | --- |
| Add comment/range | `<leader>ci` (normal/visual) | `:StagedAdd` (cursor line) |
| Edit / delete | `<leader>ce` / `<leader>cd` | `:StagedEdit` / `:StagedDelete` |
| Clear session comments | `<leader>cD` | `:StagedClear` |
| Undo / redo comment change | `<leader>cu` / `<leader>cr` | `:StagedUndo` / `:StagedRedo` |
| Toggle sidebar | `<leader>cs` | `:StagedToggle` |
| Export to clipboard / buffer / file | `<leader>cy` / `<leader>cb` / `<leader>cw` | `:StagedExport [destination] [format]` |
| Next / previous comment in this file | `]m` / `[m` | — |
| Activate in manual mode | — | `:StagedEnable` |

**Sidebar:** `<CR>` jumps, `e` edits, `d` deletes, `q` closes. Export, clear, and undo/redo
keys also work here.

**Floating input:** `<C-s>` saves; `<CR>` saves in Normal mode. `<Esc>` leaves Insert mode,
then cancels in Normal mode; `q` also cancels in Normal mode. The window sizes to wrapped
and multiline content and adjusts when the terminal resizes.

## revisions, pull requests, and history

Use `:CodeDiff --staged`, `:CodeDiff history`, or `:CodeDiff pr <number>`, then comment normally.
Working-tree, index, and commit-revision comments are separate, even for the same path.
Changing only the base revision retains the same comments. Working-tree/index identities
are mutable, not immutable review snapshots. Original-only/deleted-file views cannot receive comments.

Sidebar headers distinguish revisions. Navigation restores the saved selection or bare
comparison; later selection, tab leave/close, or comment deletion cancels a pending jump.
Unavailable comparisons produce a notification. This does not cancel Git work already
submitted to codediff. staged.nvim neither fetches PRs nor publishes reviews or changes Git state.

## export

```vim
:StagedExport buffer markdown
:StagedExport clipboard plain
:StagedExport file json
```

Destinations are `clipboard` (default), `buffer`, and `file` (prompts for a path).
Formats are `markdown` (default), `plain`, and `json`; an omitted format uses `export.format`.
All formats can include code snippets (`export.include_code`).

```json
{"comments":[{"end_line":10,"modified_revision":"WORKING","path":"lua/example.lua","side":"modified","start_line":10,"text":"needs error handling"}],"schema_version":2}
```

JSON schema 2 replaces schema 1: check `schema_version`. Records include `modified_revision`
(`WORKING`, `:0`, or a commit revision), `original_revision` when known, and `side: "modified"`.
Line ranges are 1-based and inclusive; keys are sorted for deterministic output.
Paths are relative to the session root; JSON omits paths outside it.
Positions and snippets are captured before buffers unload so exports and undo survive file switches.

For a scripted file export: `require('staged.export').to_file(path, { format = 'json' })`.

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

Comment mutations emit these `User` events:

- `StagedCommentAdded`, `StagedCommentEdited`, `StagedCommentDeleted`
- `StagedCommentsCleared`
- `StagedCommentsChanged` — every mutation, undo, and redo

`args.data` contains `tabpage`, `action`, and `total_count`. Per-comment events also include
`comment_id`, `file_path`, `modified_revision`, and a snapshot without internal extmark state.

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

[MIT](LICENSE).
