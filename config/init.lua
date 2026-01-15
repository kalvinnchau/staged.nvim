-- Minimal config for barebones testing of staged.nvim
-- Loads only this plugin with no user config or other plugins
-- Usage: nvim -u config/init.lua

-- Don't load user config
vim.opt.shadafile = 'NONE'

-- Add plugin to runtimepath
local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
vim.opt.rtp:prepend(plugin_dir)

-- Setup the plugin
require('staged').setup()

-- Print confirmation
vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    print('staged.nvim loaded. Test with:')
    print('  :lua print(vim.inspect(require("staged.config").options))')
    print('  :lua require("staged").setup({ sidebar = { width = 50 } })')
    print('  :lua print(require("staged.config").options.sidebar.width)')
  end,
})
