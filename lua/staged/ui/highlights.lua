local M = {}

---Namespace for inline indicators
M.ns_indicators = vim.api.nvim_create_namespace('staged-indicators')

---Setup highlight groups
function M.setup()
  -- Define highlight groups with sensible defaults
  vim.api.nvim_set_hl(0, 'StagedCommentSign', { link = 'DiagnosticInfo', default = true })
  vim.api.nvim_set_hl(0, 'StagedCommentVirtText', { link = 'Comment', default = true })
  vim.api.nvim_set_hl(0, 'StagedCommentLine', { bg = '#2d3f4f', default = true })
  vim.api.nvim_set_hl(0, 'StagedSidebarFile', { link = 'Directory', default = true })
  vim.api.nvim_set_hl(0, 'StagedSidebarLineNr', { link = 'LineNr', default = true })
  vim.api.nvim_set_hl(0, 'StagedSidebarComment', { link = 'Normal', default = true })
  vim.api.nvim_set_hl(0, 'StagedInputBorder', { link = 'FloatBorder', default = true })
end

return M
