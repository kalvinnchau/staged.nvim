local M = {}

local function define()
  vim.api.nvim_set_hl(0, 'StagedCommentSign', { link = 'DiagnosticInfo', default = true })
  vim.api.nvim_set_hl(0, 'StagedCommentVirtText', { link = 'Comment', default = true })
  vim.api.nvim_set_hl(0, 'StagedCommentLine', { link = 'CursorLine', default = true })
  vim.api.nvim_set_hl(0, 'StagedSidebarFile', { link = 'Directory', default = true })
  vim.api.nvim_set_hl(0, 'StagedSidebarLineNr', { link = 'LineNr', default = true })
  vim.api.nvim_set_hl(0, 'StagedSidebarComment', { link = 'Normal', default = true })
  vim.api.nvim_set_hl(0, 'StagedInputBorder', { link = 'FloatBorder', default = true })
end

---Setup highlight groups
function M.setup()
  define()

  local group = vim.api.nvim_create_augroup('staged-highlights', { clear = true })
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = define,
  })
end

return M
