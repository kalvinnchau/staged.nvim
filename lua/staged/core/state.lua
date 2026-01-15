local M = {}

---@type table<integer, StagedSession> Sessions indexed by tabpage ID
local sessions = {}

---@param tabpage integer Tabpage ID
---@return StagedSession
function M.create_session(tabpage)
  local ns_id = vim.api.nvim_create_namespace('staged-' .. tabpage)

  ---@type StagedSession
  local session = {
    tabpage = tabpage,
    files = {},
    current_file = nil,
    sidebar_bufnr = nil,
    sidebar_winid = nil,
    visible = false,
    ns_id = ns_id,
  }

  sessions[tabpage] = session
  return session
end

---@param tabpage integer
---@return StagedSession|nil
function M.get_session(tabpage)
  return sessions[tabpage]
end

---@return StagedSession|nil
function M.get_current_session()
  local tabpage = vim.api.nvim_get_current_tabpage()
  return sessions[tabpage]
end

---Set the current file for a session, creating file state if needed
---@param session StagedSession
---@param file_path string
---@param bufnr integer
function M.set_current_file(session, file_path, bufnr)
  session.current_file = file_path

  -- Create file state if it doesn't exist
  if not session.files[file_path] then
    ---@type StagedFileState
    session.files[file_path] = {
      bufnr = bufnr,
      comments = {},
    }
  else
    -- Update buffer number in case it changed
    session.files[file_path].bufnr = bufnr
  end
end

---Get the current file's state
---@param session StagedSession
---@return StagedFileState|nil
function M.get_current_file_state(session)
  if not session.current_file then
    return nil
  end
  return session.files[session.current_file]
end

---Get file state by path
---@param session StagedSession
---@param file_path string
---@return StagedFileState|nil
function M.get_file_state(session, file_path)
  return session.files[file_path]
end

---Get current buffer number
---@param session StagedSession
---@return integer|nil
function M.get_current_bufnr(session)
  local file_state = M.get_current_file_state(session)
  return file_state and file_state.bufnr or nil
end

---Get current file path
---@param session StagedSession
---@return string|nil
function M.get_current_path(session)
  return session.current_file
end

---@param tabpage integer
function M.destroy_session(tabpage)
  local session = sessions[tabpage]
  if session then
    -- Clean up extmarks for all files
    for _, file_state in pairs(session.files) do
      if vim.api.nvim_buf_is_valid(file_state.bufnr) then
        vim.api.nvim_buf_clear_namespace(file_state.bufnr, session.ns_id, 0, -1)
      end
    end
    -- Clean up sidebar
    if session.sidebar_bufnr and vim.api.nvim_buf_is_valid(session.sidebar_bufnr) then
      vim.api.nvim_buf_delete(session.sidebar_bufnr, { force = true })
    end
  end
  sessions[tabpage] = nil
end

---@return table<integer, StagedSession>
function M.get_all_sessions()
  return sessions
end

---Count total comments across all files
---@param session StagedSession
---@return integer
function M.total_comment_count(session)
  local count = 0
  for _, file_state in pairs(session.files) do
    for _ in pairs(file_state.comments) do
      count = count + 1
    end
  end
  return count
end

return M
