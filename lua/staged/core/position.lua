local M = {}

---@param file_state StagedFileState
---@param start_line integer
---@param end_line integer
---@return integer, integer
local function clamp_lines(file_state, start_line, end_line)
  if not vim.api.nvim_buf_is_valid(file_state.bufnr) then
    return start_line, end_line
  end

  if not vim.api.nvim_buf_is_loaded(file_state.bufnr) then
    return start_line, end_line
  end

  local line_count = vim.api.nvim_buf_line_count(file_state.bufnr)
  if line_count < 1 then
    return start_line, end_line
  end

  local clamped_start = math.max(1, math.min(start_line, line_count))
  local clamped_end = math.max(clamped_start, math.min(end_line, line_count))
  return clamped_start, clamped_end
end

---Create an extmark to track comment position
---@param session StagedSession
---@param file_state StagedFileState
---@param comment StagedComment
---@return integer|nil extmark_id
function M.create_mark(session, file_state, comment)
  if
    not vim.api.nvim_buf_is_valid(file_state.bufnr)
    or not vim.api.nvim_buf_is_loaded(file_state.bufnr)
  then
    return nil
  end

  local line_count = vim.api.nvim_buf_line_count(file_state.bufnr)
  local start_row = math.min(comment.start_line - 1, line_count - 1)
  local end_row = math.min(comment.end_line - 1, line_count - 1)
  start_row = math.max(0, start_row)
  end_row = math.max(start_row, end_row)

  local end_line = vim.api.nvim_buf_get_lines(file_state.bufnr, end_row, end_row + 1, false)[1]
    or ''

  -- Extmarks are 0-indexed, comments are 1-indexed
  local extmark_id = vim.api.nvim_buf_set_extmark(file_state.bufnr, session.ns_id, start_row, 0, {
    end_row = end_row,
    end_col = #end_line,
    right_gravity = true,
    end_right_gravity = false,
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
  local start_line = comment.start_line
  local end_line = comment.end_line

  if not vim.api.nvim_buf_is_valid(file_state.bufnr) then
    return start_line, end_line
  end

  if not comment.extmark_id then
    return clamp_lines(file_state, start_line, end_line)
  end

  local ok, mark =
    pcall(vim.api.nvim_buf_get_extmark_by_id, file_state.bufnr, session.ns_id, comment.extmark_id, {
      details = true,
    })

  if ok and mark and #mark > 0 then
    start_line = mark[1] + 1 -- Convert to 1-indexed
    local details = mark[3]
    end_line = details and details.end_row and (details.end_row + 1) or start_line
  end

  return clamp_lines(file_state, start_line, end_line)
end

return M
