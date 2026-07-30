-- Config for testing staged.nvim with codediff.nvim integration
-- Usage: nvim -u config/with_codediff.lua

-- Don't load user config
vim.opt.shadafile = 'NONE'

-- Set leader to comma
vim.g.mapleader = ','

-- Add plugin to runtimepath
local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
vim.opt.rtp:prepend(plugin_dir)
vim.cmd('runtime plugin/staged.lua')

-- Add codediff.nvim (assumes installed via lazy.nvim)
local codediff_dir = vim.fn.stdpath('data') .. '/lazy/codediff.nvim'
if vim.fn.isdirectory(codediff_dir) == 1 then
  vim.opt.rtp:prepend(codediff_dir)
  require('codediff').setup()
else
  vim.notify('codediff.nvim not found at: ' .. codediff_dir, vim.log.levels.WARN)
end

-- Setup staged
require('staged').setup()

-- Print confirmation
vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    local codediff = require('staged.integration.codediff')
    print('staged.nvim loaded with codediff integration')
    print('codediff available: ' .. tostring(codediff.is_available()))
    print('')
    print('Test workflow:')
    print('  1. Open a file with git changes')
    print('  2. :CodeDiff')
    print('  3. :lua print(vim.inspect(require("staged.core.state").get_current_session()))')
    print('')
    print('Test sidebar (after CodeDiff):')
    print('  -- Add comment:')
    print('  :lua require("staged.core.comments").add(5, 5, "Test comment")')
    print('  -- Show sidebar:')
    print('  :lua require("staged.ui.sidebar").show(require("staged.core.state").get_current_session())')
    print('  -- Sidebar keymaps: <CR>=goto, e=edit, d=delete, q=close')
    print('  -- Toggle sidebar:')
    print('  :lua require("staged.ui.sidebar").toggle(require("staged.core.state").get_current_session())')
    print('')
    print('Test export (after adding comments):')
    print('  :lua require("staged.export").to_clipboard()')
    print('  :lua require("staged.export").to_buffer()')
    print('  :lua require("staged.export").to_file()')
  end,
})
