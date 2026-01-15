-- Minimal init for tests
vim.opt.shadafile = 'NONE'

-- Add plugin to rtp
local plugin_dir = vim.fn.getcwd()
vim.opt.rtp:prepend(plugin_dir)

-- Add plenary
local plenary_dir = vim.fn.stdpath('data') .. '/lazy/plenary.nvim'
vim.opt.rtp:prepend(plenary_dir)

-- Add codediff
local codediff_dir = vim.fn.stdpath('data') .. '/lazy/codediff.nvim'
vim.opt.rtp:prepend(codediff_dir)

-- Load plugin
require('staged').setup()
