# staged.nvim

Ephemeral comments for codediff.nvim diffs.

## Design
- Session-scoped to tabpage - comments are ephemeral, lost on tab close
- Modified-side only - comments attach to right buffer, never original
- Extmarks track positions as buffer changes
- Core/UI split: `core/` = logic, `ui/` = presentation

## codediff.nvim
- `require('codediff.ui.lifecycle').get_session(tabpage)` for access
- Never modify codediff state or use its namespaces
- Own namespace: `staged-{tabpage}`

## Gotchas
- Extmarks are 0-indexed, comment lines are 1-indexed - always convert

## Entry Points
- `lua/staged/init.lua` - setup() and public API
- `lua/staged/core/state.lua` - session management
- `lua/staged/core/comments.lua` - CRUD operations

## Conventions
- 2-space indent, single quotes, `local` everything
- Types in `lua/staged/types.lua`
- `vim.notify()` for user messages
- `just fmt && just test` before commit

## Tools
- Uses [mise](https://mise.jdx.dev/) for tool management
- Run `mise install` to install dependencies (just, stylua)
- justfile uses `mise x --` to invoke tools

## Testing
- `config/init.lua` - barebones Neovim config for manual testing
- Usage: `nvim -u config/init.lua`
