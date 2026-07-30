local M = {}

---@type table<integer, StagedSession> Sessions indexed by tabpage ID
local sessions = {}

---@class StagedManagedKeymap
---@field owners table<StagedSession, boolean>
---@field previous? table
---@field rhs string|function

---@type table<integer, table<string, StagedManagedKeymap>>
local managed_keymaps = {}

---@param tabpage integer Tabpage ID
---@return StagedSession
function M.create_session(tabpage)
  local ns_id = vim.api.nvim_create_namespace('staged-' .. tabpage)
  local indicator_ns_id = vim.api.nvim_create_namespace('staged-indicators-' .. tabpage)

  ---@type StagedSession
  local session = {
    tabpage = tabpage,
    files = {},
    current_file = nil,
    sidebar_bufnr = nil,
    sidebar_winid = nil,
    visible = false,
    ns_id = ns_id,
    indicator_ns_id = indicator_ns_id,
    keymaps = {},
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

---@param bufnr integer
---@param mode string
---@param lhs string
---@return table|nil
local function get_buffer_keymap(bufnr, mode, lhs)
  local ok, mapping = pcall(vim.api.nvim_buf_call, bufnr, function()
    return vim.fn.maparg(lhs, mode, false, true)
  end)
  if ok and type(mapping) == 'table' and mapping.buffer == 1 then
    return mapping
  end
  return nil
end

---@param bufnr integer
---@param mode string
---@param lhs string
---@param mapping table
local function restore_keymap(bufnr, mode, lhs, mapping)
  local rhs = mapping.callback or mapping.rhs
  if not rhs then
    return
  end

  pcall(vim.keymap.set, mapping.mode or mode, lhs, rhs, {
    buffer = bufnr,
    desc = mapping.desc,
    expr = mapping.expr == 1,
    nowait = mapping.nowait == 1,
    remap = mapping.noremap == 0,
    replace_keycodes = mapping.replace_keycodes == 1,
    script = mapping.script == 1,
    silent = mapping.silent == 1,
  })
end

---@param mapping table|nil
---@param rhs string|function
---@return boolean
local function matches_keymap(mapping, rhs)
  if not mapping then
    return false
  end
  if type(rhs) == 'function' then
    return mapping.callback == rhs
  end
  return mapping.rhs == rhs
end

---@param session StagedSession
---@param bufnr integer
---@param mode string
---@param lhs string
---@param rhs string|function
---@param opts? table
function M.set_keymap(session, bufnr, mode, lhs, rhs, opts)
  local key = mode .. '\0' .. lhs
  local buffer_keymaps = managed_keymaps[bufnr]
  local managed = buffer_keymaps and buffer_keymaps[key] or nil
  local previous = managed and managed.previous or get_buffer_keymap(bufnr, mode, lhs)

  opts = vim.tbl_extend('force', opts or {}, { buffer = bufnr })
  vim.keymap.set(mode, lhs, rhs, opts)

  if not managed then
    buffer_keymaps = buffer_keymaps or {}
    managed_keymaps[bufnr] = buffer_keymaps
    managed = {
      owners = {},
      previous = previous,
      rhs = rhs,
    }
    buffer_keymaps[key] = managed
  end

  managed.rhs = rhs
  managed.owners[session] = true
  session.keymaps[bufnr] = session.keymaps[bufnr] or {}
  session.keymaps[bufnr][key] = {
    mode = mode,
    lhs = lhs,
  }
end

---@param session StagedSession
---@param bufnr? integer
function M.clear_keymaps(session, bufnr)
  local keymaps = bufnr and { [bufnr] = session.keymaps[bufnr] } or session.keymaps

  for buffer, mappings in pairs(keymaps) do
    for key, mapping in pairs(mappings or {}) do
      local managed = managed_keymaps[buffer] and managed_keymaps[buffer][key]
      if managed then
        managed.owners[session] = nil
      end

      if not managed or next(managed.owners) == nil then
        local current = managed and get_buffer_keymap(buffer, mapping.mode, mapping.lhs) or nil
        if managed and matches_keymap(current, managed.rhs) then
          if managed.previous then
            restore_keymap(buffer, mapping.mode, mapping.lhs, managed.previous)
          else
            pcall(vim.keymap.del, mapping.mode, mapping.lhs, { buffer = buffer })
          end
        end

        if managed_keymaps[buffer] then
          managed_keymaps[buffer][key] = nil
        end
      end
    end

    if managed_keymaps[buffer] and next(managed_keymaps[buffer]) == nil then
      managed_keymaps[buffer] = nil
    end
    session.keymaps[buffer] = nil
  end
end

---Set the current file for a session, creating file state if needed
---@param session StagedSession
---@param file_path string
---@param bufnr integer
function M.set_current_file(session, file_path, bufnr)
  local previous_path = session.current_file
  local previous_state = previous_path and session.files[previous_path] or nil

  if previous_state and (previous_path ~= file_path or previous_state.bufnr ~= bufnr) then
    M.clear_keymaps(session, previous_state.bufnr)
    if vim.api.nvim_buf_is_valid(previous_state.bufnr) then
      vim.api.nvim_buf_clear_namespace(previous_state.bufnr, session.indicator_ns_id, 0, -1)
    end
  end

  session.current_file = file_path

  if not session.files[file_path] then
    ---@type StagedFileState
    session.files[file_path] = {
      bufnr = bufnr,
      comments = {},
    }
    return
  end

  local file_state = session.files[file_path]
  if file_state.bufnr == bufnr then
    return
  end

  local position = require('staged.core.position')
  for _, comment in pairs(file_state.comments) do
    local start_line, end_line = position.get_current_lines(session, file_state, comment)
    position.delete_mark(session, file_state, comment)
    comment.start_line = start_line
    comment.end_line = end_line
  end

  file_state.bufnr = bufnr
  for _, comment in pairs(file_state.comments) do
    comment.extmark_id = position.create_mark(session, file_state, comment)
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
    M.clear_keymaps(session)

    for _, file_state in pairs(session.files) do
      if vim.api.nvim_buf_is_valid(file_state.bufnr) then
        vim.api.nvim_buf_clear_namespace(file_state.bufnr, session.ns_id, 0, -1)
        vim.api.nvim_buf_clear_namespace(file_state.bufnr, session.indicator_ns_id, 0, -1)
      end
    end

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
