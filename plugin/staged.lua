-- Plugin autoload file
-- This runs when Neovim starts (or when plugin is lazy-loaded)

if vim.g.loaded_staged then
  return
end
vim.g.loaded_staged = true

-- Commands
local export_destinations = { 'clipboard', 'buffer', 'file' }
local export_formats = { 'markdown', 'plain', 'json' }

---@param values string[]
---@param value string
---@return boolean
local function contains(values, value)
  return vim.tbl_contains(values, value)
end

---@param arg_lead string
---@param command_line string
---@param cursor_position integer
---@return string[]
local function complete_export(arg_lead, command_line, cursor_position)
  local before_cursor = command_line:sub(1, cursor_position)
  local command
  local next_command = before_cursor
  while next_command ~= '' do
    local ok, parsed = pcall(vim.api.nvim_parse_cmd, next_command, {})
    if not ok then
      return {}
    end
    command = parsed
    next_command = parsed.nextcmd or ''
  end

  if not command or command.cmd ~= 'StagedExport' then
    return {}
  end

  local index = #command.args + (before_cursor:match('%s$') and 1 or 0)
  local candidates = index <= 1 and export_destinations or index == 2 and export_formats or {}

  return vim.tbl_filter(function(value)
    return vim.startswith(value, arg_lead)
  end, candidates)
end

vim.api.nvim_create_user_command('StagedAdd', function()
  require('staged').add_comment_interactive()
end, { desc = 'Add a comment at cursor' })

vim.api.nvim_create_user_command('StagedEdit', function()
  require('staged').edit_comment_at_cursor()
end, { desc = 'Edit comment at cursor' })

vim.api.nvim_create_user_command('StagedDelete', function()
  require('staged').delete_comment_at_cursor()
end, { desc = 'Delete comment at cursor' })

vim.api.nvim_create_user_command('StagedClear', function()
  require('staged').clear_all()
end, { desc = 'Clear all comments' })

vim.api.nvim_create_user_command('StagedUndo', function()
  require('staged').undo()
end, { desc = 'Undo the last comment change' })

vim.api.nvim_create_user_command('StagedRedo', function()
  require('staged').redo()
end, { desc = 'Redo the last undone comment change' })

vim.api.nvim_create_user_command('StagedToggle', function()
  require('staged').toggle_sidebar()
end, { desc = 'Toggle sidebar' })

vim.api.nvim_create_user_command('StagedExport', function(opts)
  local destination = opts.fargs[1] or 'clipboard'
  local format = opts.fargs[2]
  if not contains(export_destinations, destination) then
    vim.notify('Unknown destination: ' .. destination, vim.log.levels.ERROR)
    return
  end
  if format and not contains(export_formats, format) then
    vim.notify('Unknown format: ' .. format, vim.log.levels.ERROR)
    return
  end
  if #opts.fargs > 2 then
    vim.notify('Usage: StagedExport [destination] [format]', vim.log.levels.ERROR)
    return
  end

  local export = require('staged.export')
  local export_opts = format and { format = format } or nil
  if destination == 'clipboard' then
    export.to_clipboard(export_opts)
  elseif destination == 'buffer' then
    export.to_buffer(export_opts)
  else
    export.to_file(nil, export_opts)
  end
end, {
  nargs = '*',
  complete = complete_export,
  desc = 'Export comments',
})

vim.api.nvim_create_user_command('StagedEnable', function()
  require('staged').enable()
end, { desc = 'Enable staged for current codediff' })
