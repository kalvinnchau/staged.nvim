# staged.nvim

ephemeral comments for [codediff.nvim](https://github.com/esmuellert/codediff.nvim) diffs.

comments live on the modified side, track line positions, and disappear when the tab closes.

## requirements

- neovim >= 0.10.0
- [codediff.nvim](https://github.com/esmuellert/codediff.nvim)
- optionally, a clipboard provider for clipboard exports (`:checkhealth provider`)

## install

```lua
-- lazy.nvim
{
  'kalvinnchau/staged.nvim',
  dependencies = { 'esmuellert/codediff.nvim' },
  opts = {},
}
```

## config

```lua
-- lazy.nvim
{
  'kalvinnchau/staged.nvim',
  dependencies = { 'esmuellert/codediff.nvim' },
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
      virtual_text_format = '[%d comment(s)]', -- string.format pattern
    },
    input = {
      style = 'floating', -- 'floating' or vim.ui.input-backed 'inline'
    },
    export = {
      include_code = true, -- include code snippets in export
      format = 'markdown',  -- 'markdown' or 'plain'
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
- `<leader>cs` - toggle sidebar
- `<leader>cy` - export to clipboard
- `<leader>cb` - export to buffer
- `<leader>cw` - export to file
- `]m` / `[m` - next/prev comment

in sidebar:

- `<CR>` - jump to comment
- `e` - edit comment
- `d` - delete comment
- `q` - close sidebar

in the floating input window:

- `<C-s>` - save comment
- `<CR>` - save (normal mode)
- `<Esc>` - cancel
- `q` - cancel

## commands

- `:StagedAdd` - add comment at cursor
- `:StagedEdit` - edit comment at cursor
- `:StagedDelete` - delete comment at cursor
- `:StagedClear` - clear all comments
- `:StagedToggle` - toggle sidebar
- `:StagedExport [clipboard|buffer|file]` - export comments
- `:StagedEnable` - enable for current codediff (manual mode)

## export

outputs markdown or plain text with optional code snippets:

```markdown
## path/to/file.lua

- **Line 10**: needs error handling
```

## development

requires neovim, [plenary.nvim](https://github.com/nvim-lua/plenary.nvim), and
[mise](https://mise.jdx.dev/) for tool management. the test config expects plenary.nvim at
`stdpath('data')/lazy/plenary.nvim`.

```bash
mise install          # install neovim, just, stylua
just fmt              # format code
just test             # run tests
just lint             # check formatting
```

manual testing:

```bash
nvim -u config/with_codediff.lua   # test with codediff integration
nvim -u config/init.lua            # test plugin only
```

## license

MIT. See [LICENSE](LICENSE) for details.
