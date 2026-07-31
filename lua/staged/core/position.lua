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

---Create an extmark to track a line range
---@param namespace integer
---@param file_state StagedFileState
---@param start_line integer
---@param end_line integer
---@return integer|nil extmark_id
function M.create_range_mark(namespace, file_state, start_line, end_line)
  if
    not vim.api.nvim_buf_is_valid(file_state.bufnr)
    or not vim.api.nvim_buf_is_loaded(file_state.bufnr)
  then
    return nil
  end

  local line_count = vim.api.nvim_buf_line_count(file_state.bufnr)
  local start_row = math.min(start_line - 1, line_count - 1)
  local end_row = math.min(end_line - 1, line_count - 1)
  start_row = math.max(0, start_row)
  end_row = math.max(start_row, end_row)

  local end_line = vim.api.nvim_buf_get_lines(file_state.bufnr, end_row, end_row + 1, false)[1]
    or ''

  -- Extmarks are 0-indexed, comments are 1-indexed
  local extmark_id = vim.api.nvim_buf_set_extmark(file_state.bufnr, namespace, start_row, 0, {
    end_row = end_row,
    end_col = #end_line,
    right_gravity = true,
    end_right_gravity = false,
  })
  return extmark_id
end

---Create an extmark to track comment position
---@param session StagedSession
---@param file_state StagedFileState
---@param comment StagedComment
---@return integer|nil extmark_id
function M.create_mark(session, file_state, comment)
  return M.create_range_mark(session.ns_id, file_state, comment.start_line, comment.end_line)
end

---Delete a range extmark
---@param namespace integer
---@param file_state StagedFileState
---@param extmark_id integer|nil
function M.delete_range_mark(namespace, file_state, extmark_id)
  if extmark_id then
    pcall(vim.api.nvim_buf_del_extmark, file_state.bufnr, namespace, extmark_id)
  end
end

---Delete extmark for a comment
---@param session StagedSession
---@param file_state StagedFileState
---@param comment StagedComment
function M.delete_mark(session, file_state, comment)
  M.delete_range_mark(session.ns_id, file_state, comment.extmark_id)
end

---Get current line positions for a range extmark
---@param namespace integer
---@param file_state StagedFileState
---@param extmark_id integer|nil
---@param start_line integer
---@param end_line integer
---@return integer start_line, integer end_line (1-indexed)
function M.get_range_mark_lines(namespace, file_state, extmark_id, start_line, end_line)
  if not vim.api.nvim_buf_is_valid(file_state.bufnr) then
    return start_line, end_line
  end

  if not extmark_id then
    return clamp_lines(file_state, start_line, end_line)
  end

  local ok, mark =
    pcall(vim.api.nvim_buf_get_extmark_by_id, file_state.bufnr, namespace, extmark_id, {
      details = true,
    })

  if ok and mark and #mark > 0 then
    start_line = mark[1] + 1 -- Convert to 1-indexed
    local details = mark[3]
    end_line = details and details.end_row and (details.end_row + 1) or start_line
  end

  return clamp_lines(file_state, start_line, end_line)
end

---Get current line positions for a comment (may have shifted)
---@param session StagedSession
---@param file_state StagedFileState
---@param comment StagedComment
---@return integer start_line, integer end_line (1-indexed)
function M.get_current_lines(session, file_state, comment)
  return M.get_range_mark_lines(
    session.ns_id,
    file_state,
    comment.extmark_id,
    comment.start_line,
    comment.end_line
  )
end

return M
