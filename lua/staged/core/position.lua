local M = {}

---Create an extmark to track comment position
---@param session StagedSession
---@param file_state StagedFileState
---@param comment StagedComment
---@return integer|nil extmark_id
function M.create_mark(session, file_state, comment)
  -- Validate buffer and line range
  if not vim.api.nvim_buf_is_valid(file_state.bufnr) then
    return nil
  end

  local line_count = vim.api.nvim_buf_line_count(file_state.bufnr)
  local start_row = math.min(comment.start_line - 1, line_count - 1)
  local end_row = math.min(comment.end_line - 1, line_count - 1)
  start_row = math.max(0, start_row)
  end_row = math.max(start_row, end_row)

  -- Extmarks are 0-indexed, comments are 1-indexed
  local extmark_id = vim.api.nvim_buf_set_extmark(file_state.bufnr, session.ns_id, start_row, 0, {
    end_row = end_row,
    end_col = 0,
    -- right_gravity = false means mark stays at original position
    -- when text is inserted at the mark position
    right_gravity = false,
  })
  return extmark_id
end

---Delete extmark for a comment
---@param session StagedSession
---@param file_state StagedFileState
---@param comment StagedComment
function M.delete_mark(session, file_state, comment)
  if comment.extmark_id then
    pcall(vim.api.nvim_buf_del_extmark, file_state.bufnr, session.ns_id, comment.extmark_id)
  end
end

---Get current line positions for a comment (may have shifted)
---@param session StagedSession
---@param file_state StagedFileState
---@param comment StagedComment
---@return integer start_line, integer end_line (1-indexed)
function M.get_current_lines(session, file_state, comment)
  if not comment.extmark_id then
    return comment.start_line, comment.end_line
  end

  local mark = vim.api.nvim_buf_get_extmark_by_id(
    file_state.bufnr,
    session.ns_id,
    comment.extmark_id,
    { details = true }
  )

  if mark and #mark > 0 then
    local start_line = mark[1] + 1 -- Convert to 1-indexed
    local details = mark[3]
    local end_line = details and details.end_row and (details.end_row + 1) or start_line
    return start_line, end_line
  end

  -- Fallback to original position
  return comment.start_line, comment.end_line
end

return M
