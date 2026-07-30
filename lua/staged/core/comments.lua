local M = {}

local state = require('staged.core.state')
local position = require('staged.core.position')

local id_counter = 0

---Generate a UUID v4
---@return string
local function uuid()
  id_counter = id_counter + 1
  local hash = vim.fn.sha256(
    table.concat({ tostring(vim.uv.hrtime()), tostring(os.time()), tostring(id_counter) }, ':')
  )
  local variant = ({ '8', '9', 'a', 'b' })[(tonumber(hash:sub(17, 17), 16) % 4) + 1]
  return table.concat({
    hash:sub(1, 8),
    '-',
    hash:sub(9, 12),
    '-4',
    hash:sub(14, 16),
    '-',
    variant,
    hash:sub(18, 20),
    '-',
    hash:sub(21, 32),
  })
end

---@param session? StagedSession
---@return StagedSession|nil
local function resolve_session(session)
  return session or state.get_current_session()
end

---@param session StagedSession
---@param file_state StagedFileState
---@param list StagedComment[]
local function sort_comments(session, file_state, list)
  local lines = {}
  for _, comment in ipairs(list) do
    local start_line, end_line = position.get_current_lines(session, file_state, comment)
    lines[comment.id] = { start_line, end_line }
  end

  table.sort(list, function(a, b)
    local a_lines = lines[a.id]
    local b_lines = lines[b.id]
    if a_lines[1] ~= b_lines[1] then
      return a_lines[1] < b_lines[1]
    end
    if a_lines[2] ~= b_lines[2] then
      return a_lines[2] < b_lines[2]
    end
    if a.created_at ~= b.created_at then
      return a.created_at < b.created_at
    end
    return a.id < b.id
  end)
end

---Add a new comment to the current file
---@param start_line integer 1-based start line
---@param end_line integer 1-based end line
---@param text string Comment text
---@param session? StagedSession
---@return StagedComment|nil comment The created comment, or nil if no session
function M.add(start_line, end_line, text, session)
  session = resolve_session(session)
  if not session then
    vim.notify('No active staged session', vim.log.levels.WARN)
    return nil
  end

  if
    type(start_line) ~= 'number'
    or type(end_line) ~= 'number'
    or start_line % 1 ~= 0
    or end_line % 1 ~= 0
    or start_line < 1
    or end_line < start_line
  then
    vim.notify('Invalid comment line range', vim.log.levels.ERROR)
    return nil
  end

  if type(text) ~= 'string' or vim.trim(text) == '' then
    vim.notify('Comment text cannot be empty', vim.log.levels.ERROR)
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
---@param session? StagedSession
---@return boolean success
function M.edit(comment_id, new_text, session)
  session = resolve_session(session)
  if not session then
    return false
  end

  if type(new_text) ~= 'string' or vim.trim(new_text) == '' then
    vim.notify('Comment text cannot be empty', vim.log.levels.ERROR)
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
---@param session? StagedSession
---@return boolean success
function M.delete(comment_id, session)
  session = resolve_session(session)
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
---@param session? StagedSession
function M.clear_current_file(session)
  session = resolve_session(session)
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
---@param session? StagedSession
function M.clear_all(session)
  session = resolve_session(session)
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
---@param session? StagedSession
---@return StagedComment|nil
function M.get_at_line(line, session)
  session = resolve_session(session)
  if not session then
    return nil
  end

  local file_state = state.get_current_file_state(session)
  if not file_state then
    return nil
  end

  for _, comment in ipairs(M.get_sorted(session)) do
    local current_start, current_end = position.get_current_lines(session, file_state, comment)
    if line >= current_start and line <= current_end then
      return comment
    end
  end

  return nil
end

---Get all comments in current file sorted by line number
---@param session? StagedSession
---@return StagedComment[]
function M.get_sorted(session)
  session = resolve_session(session)
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

  sort_comments(session, file_state, list)

  return list
end

---Get all comments across all files, grouped by file path
---@param session? StagedSession
---@return table<string, StagedComment[]> comments grouped by file path
function M.get_all_grouped(session)
  session = resolve_session(session)
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
      sort_comments(session, file_state, list)
      result[file_path] = list
    end
  end

  return result
end

---Get count of comments in current file
---@param session? StagedSession
---@return integer
function M.count(session)
  session = resolve_session(session)
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
---@param session? StagedSession
---@return integer
function M.total_count(session)
  session = resolve_session(session)
  if not session then
    return 0
  end
  return state.total_comment_count(session)
end

return M
