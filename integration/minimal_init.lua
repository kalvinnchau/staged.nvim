vim.opt.shadafile = 'NONE'
vim.opt.swapfile = false
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.env.VSCODE_DIFF_NO_AUTO_INSTALL = '1'
vim.env.CODEDIFF_WATCHER_NO_AUTO_INSTALL = '1'

local data = vim.fn.stdpath('data')
for _, path in ipairs({
  vim.env.STAGED_PLENARY_PATH or (data .. '/lazy/plenary.nvim'),
  vim.env.STAGED_CODEDIFF_PATH or (data .. '/lazy/codediff.nvim'),
}) do
  assert(vim.fn.isdirectory(path) == 1, 'Missing test dependency: ' .. path)
  vim.opt.rtp:prepend(path)
end

local version = require('codediff.version').VERSION
assert(
  vim.version.cmp(version, '4.0.5') >= 0 and vim.version.cmp(version, '5.0.0') < 0,
  'Unsupported codediff version: ' .. tostring(version)
)
assert(
  require('codediff.core.diff').get_version() == version,
  'codediff native library version mismatch'
)
vim.cmd('runtime plugin/codediff.lua')
require('codediff').setup({
  diff = { disable_inlay_hints = false, gutter_signs = { changed_priority = 100 } },
  explorer = { auto_refresh = false },
})
vim.cmd('runtime plugin/staged.lua')
require('staged').setup({ sidebar = { auto_show = false } })
