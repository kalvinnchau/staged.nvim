local M = {}

---@type { pattern: string, data: table }[]
local pending = {}
local dispatching = false

local function dispatch()
  if dispatching then
    return
  end

  dispatching = true
  while #pending > 0 do
    local event = table.remove(pending, 1)
    local ok, err = pcall(vim.api.nvim_exec_autocmds, 'User', {
      pattern = event.pattern,
      modeline = false,
      data = event.data,
    })
    if not ok then
      pending = {}
      dispatching = false
      error(err, 0)
    end
  end
  dispatching = false
end

---@param session StagedSession
---@param event_specs { pattern: string, data?: table }[]
function M.emit_many(session, event_specs)
  for _, event in ipairs(event_specs) do
    table.insert(pending, {
      pattern = event.pattern,
      data = vim.tbl_extend('force', { tabpage = session.tabpage }, vim.deepcopy(event.data or {})),
    })
  end
  dispatch()
end

---@param pattern string
---@param session StagedSession
---@param data? table
function M.emit(pattern, session, data)
  M.emit_many(session, { { pattern = pattern, data = data } })
end

---@param comment StagedComment
---@param start_line? integer
---@param end_line? integer
---@return table
function M.comment_data(comment, start_line, end_line)
  return {
    id = comment.id,
    file_path = comment.file_path,
    modified_revision = comment.modified_revision,
    start_line = start_line or comment.start_line,
    end_line = end_line or comment.end_line,
    text = comment.text,
    created_at = comment.created_at,
  }
end

return M
