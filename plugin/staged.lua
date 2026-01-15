-- Plugin autoload file
-- This runs when Neovim starts (or when plugin is lazy-loaded)

if vim.g.loaded_staged then
  return
end
vim.g.loaded_staged = true

-- Commands
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

vim.api.nvim_create_user_command('StagedToggle', function()
  require('staged').toggle_sidebar()
end, { desc = 'Toggle sidebar' })

vim.api.nvim_create_user_command('StagedExport', function(opts)
  local dest = opts.args ~= '' and opts.args or 'clipboard'
  if dest == 'clipboard' then
    require('staged.export').to_clipboard()
  elseif dest == 'buffer' then
    require('staged.export').to_buffer()
  elseif dest == 'file' then
    require('staged.export').to_file()
  else
    vim.notify('Unknown destination: ' .. dest, vim.log.levels.ERROR)
  end
end, {
  nargs = '?',
  complete = function()
    return { 'clipboard', 'buffer', 'file' }
  end,
  desc = 'Export comments',
})

vim.api.nvim_create_user_command('StagedEnable', function()
  require('staged').enable()
end, { desc = 'Enable staged for current codediff' })
