-- Minimal init for tests
vim.opt.shadafile = 'NONE'

-- Add plugin to rtp
local plugin_dir = vim.fn.getcwd()
vim.opt.rtp:prepend(plugin_dir)

-- Add plenary
local plenary_dir = vim.fn.stdpath('data') .. '/lazy/plenary.nvim'
if vim.fn.isdirectory(plenary_dir) == 0 then
  error('plenary.nvim not found at ' .. plenary_dir)
end
vim.opt.rtp:prepend(plenary_dir)

-- Load plugin
vim.cmd('runtime plugin/staged.lua')
require('staged').setup()
