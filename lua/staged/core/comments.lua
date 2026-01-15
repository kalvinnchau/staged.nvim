local M = {}

local state = require('staged.core.state')
local position = require('staged.core.position')

---Generate a UUID v4
---@return string
local function uuid()
  local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
  return (
    template:gsub('[xy]', function(c)
      local v = c == 'x' and math.random(0, 15) or math.random(8, 11)
      return string.format('%x', v)
    end)
  )
end

---Add a new comment to the current file
---@param start_line integer 1-based start line
---@param end_line integer 1-based end line
---@param text string Comment text
---@return StagedComment|nil comment The created comment, or nil if no session
function M.add(start_line, end_line, text)
  local session = state.get_current_session()
  if not session then
    vim.notify('No active staged session', vim.log.levels.WARN)
    return nil
  end

  local file_state = state.get_current_file_state(session)
  if not file_state then
    vim.notify('No active file in session', vim.log.levels.WARN)
    return nil
  end

  ---@type StagedComment
  local comment = {
    id = uuid(),
    file_path = session.current_file,
    start_line = start_line,
    end_line = end_line,
    text = text,
    created_at = os.time(),
    extmark_id = nil,
  }

  -- Create extmark to track position
  comment.extmark_id = position.create_mark(session, file_state, comment)

  -- Store in file state
  file_state.comments[comment.id] = comment

  return comment
end

---Edit an existing comment (searches all files)
---@param comment_id string
---@param new_text string
---@return boolean success
function M.edit(comment_id, new_text)
  local session = state.get_current_session()
  if not session then
    return false
  end

  -- Search all files for the comment
  for _, file_state in pairs(session.files) do
    local comment = file_state.comments[comment_id]
    if comment then
      comment.text = new_text
      return true
    end
  end

  return false
end

---Delete a comment (searches all files)
---@param comment_id string
---@return boolean success
function M.delete(comment_id)
  local session = state.get_current_session()
  if not session then
    return false
  end

  -- Search all files for the comment
  for _, file_state in pairs(session.files) do
    local comment = file_state.comments[comment_id]
    if comment then
      position.delete_mark(session, file_state, comment)
      file_state.comments[comment_id] = nil
      return true
    end
  end

  return false
end

---Clear all comments in current file only
function M.clear_current_file()
  local session = state.get_current_session()
  if not session then
    return
  end

  local file_state = state.get_current_file_state(session)
  if not file_state then
    return
  end

  for _, comment in pairs(file_state.comments) do
    position.delete_mark(session, file_state, comment)
  end

  file_state.comments = {}
end

---Clear all comments in all files
function M.clear_all()
  local session = state.get_current_session()
  if not session then
    return
  end

  for _, file_state in pairs(session.files) do
    for _, comment in pairs(file_state.comments) do
      position.delete_mark(session, file_state, comment)
    end
    file_state.comments = {}
  end
end

---Get comment at a specific line in current file
---@param line integer 1-based line number
---@return StagedComment|nil
function M.get_at_line(line)
  local session = state.get_current_session()
  if not session then
    return nil
  end

  local file_state = state.get_current_file_state(session)
  if not file_state then
    return nil
  end

  for _, comment in pairs(file_state.comments) do
    local current_start, current_end = position.get_current_lines(session, file_state, comment)
    if line >= current_start and line <= current_end then
      return comment
    end
  end

  return nil
end

---Get all comments in current file sorted by line number
---@return StagedComment[]
function M.get_sorted()
  local session = state.get_current_session()
  if not session then
    return {}
  end

  local file_state = state.get_current_file_state(session)
  if not file_state then
    return {}
  end

  local list = {}
  for _, comment in pairs(file_state.comments) do
    table.insert(list, comment)
  end

  table.sort(list, function(a, b)
    local a_line = position.get_current_lines(session, file_state, a)
    local b_line = position.get_current_lines(session, file_state, b)
    return a_line < b_line
  end)

  return list
end

---Get all comments across all files, grouped by file path
---@return table<string, StagedComment[]> comments grouped by file path
function M.get_all_grouped()
  local session = state.get_current_session()
  if not session then
    return {}
  end

  local result = {}

  for file_path, file_state in pairs(session.files) do
    local list = {}
    for _, comment in pairs(file_state.comments) do
      table.insert(list, comment)
    end

    if #list > 0 then
      -- Sort by line number
      table.sort(list, function(a, b)
        local a_line = position.get_current_lines(session, file_state, a)
        local b_line = position.get_current_lines(session, file_state, b)
        return a_line < b_line
      end)
      result[file_path] = list
    end
  end

  return result
end

---Get count of comments in current file
---@return integer
function M.count()
  local session = state.get_current_session()
  if not session then
    return 0
  end

  local file_state = state.get_current_file_state(session)
  if not file_state then
    return 0
  end

  local count = 0
  for _ in pairs(file_state.comments) do
    count = count + 1
  end
  return count
end

---Get total count of comments across all files
---@return integer
function M.total_count()
  local session = state.get_current_session()
  if not session then
    return 0
  end
  return state.total_comment_count(session)
end

return M
