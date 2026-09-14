local M = {}

local position = require('staged.core.position')

local max_entries = 100

---Find the internal key of a file state within a session
---@param session StagedSession
---@param file_state StagedFileState
---@return string|nil
local function file_state_key(session, file_state)
  for key, state in pairs(session.files) do
    if state == file_state then
      return key
    end
  end
  return nil
end

---@param session StagedSession
---@return StagedHistory
local function get_history(session)
  if not session.history then
    session.history = {
      undo = {},
      redo = {},
    }
  end
  return session.history
end

---@param session StagedSession
---@param snapshot StagedSnapshot
local function clear_snapshot_anchors(session, snapshot)
  for file_path, saved_file in pairs(snapshot.files) do
    local file_state = session.files[file_path]
    if file_state then
      for _, comment in ipairs(saved_file.comments) do
        position.delete_range_mark(session.history_ns_id, file_state, comment.history_extmark_id)
        comment.history_extmark_id = nil
      end
    end
  end
end

---@param session StagedSession
---@param entries StagedHistoryEntry[]
local function clear_entries(session, entries)
  for _, entry in ipairs(entries) do
    clear_snapshot_anchors(session, entry.snapshot)
  end
end

---@param session StagedSession
---@param entries StagedHistoryEntry[]
local function trim(session, entries)
  if #entries > max_entries then
    local entry = table.remove(entries, 1)
    clear_snapshot_anchors(session, entry.snapshot)
  end
end

---@param session StagedSession
---@return StagedSnapshot
function M.snapshot(session)
  local snapshot = { files = {} }

  for file_key, file_state in pairs(session.files) do
    local saved_file = {
      bufnr = file_state.bufnr,
      file_path = file_state.file_path,
      modified_revision = file_state.modified_revision,
      original_revision = file_state.original_revision,
      original_path = file_state.original_path,
      git_root = file_state.git_root,
      selection = vim.deepcopy(file_state.selection),
      comments = {},
    }
    snapshot.files[file_key] = saved_file

    for _, comment in pairs(file_state.comments) do
      local start_line, end_line = position.get_current_lines(session, file_state, comment)
      table.insert(saved_file.comments, {
        id = comment.id,
        file_path = comment.file_path,
        modified_revision = comment.modified_revision,
        original_revision = comment.original_revision,
        start_line = start_line,
        end_line = end_line,
        text = comment.text,
        created_at = comment.created_at,
        created_order = comment.created_order,
        code = comment.code,
        history_extmark_id = nil,
      })
    end
  end

  return snapshot
end

---@param session StagedSession
---@param file_state StagedFileState
---@param comment StagedSavedComment
---@return integer, integer
local function get_saved_lines(session, file_state, comment)
  return position.get_range_mark_lines(
    session.history_ns_id,
    file_state,
    comment.history_extmark_id,
    comment.start_line,
    comment.end_line
  )
end

---@param session StagedSession
---@param snapshot StagedSnapshot
local function anchor_missing_comments(session, snapshot)
  for file_path, saved_file in pairs(snapshot.files) do
    local file_state = session.files[file_path]
    if file_state then
      for _, comment in ipairs(saved_file.comments) do
        if not file_state.comments[comment.id] and not comment.history_extmark_id then
          comment.history_extmark_id = position.create_range_mark(
            session.history_ns_id,
            file_state,
            comment.start_line,
            comment.end_line
          )
        end
      end
    end
  end
end

---@param session StagedSession
---@param file_state StagedFileState
---@param saved_comments StagedSavedComment[]
local function restore_file(session, file_state, saved_comments)
  local saved_by_id = {}
  for _, comment in ipairs(saved_comments) do
    saved_by_id[comment.id] = comment
  end

  for id, comment in pairs(file_state.comments) do
    if not saved_by_id[id] then
      position.delete_mark(session, file_state, comment)
      file_state.comments[id] = nil
    end
  end

  for id, saved_comment in pairs(saved_by_id) do
    local comment = file_state.comments[id]
    if comment then
      local start_line, end_line = position.get_current_lines(session, file_state, comment)
      comment.file_path = saved_comment.file_path
      comment.modified_revision = saved_comment.modified_revision
      comment.original_revision = saved_comment.original_revision
      comment.start_line = start_line
      comment.end_line = end_line
      comment.text = saved_comment.text
      comment.created_at = saved_comment.created_at
      comment.created_order = saved_comment.created_order
      comment.code = saved_comment.code
    else
      local start_line, end_line = get_saved_lines(session, file_state, saved_comment)
      comment = {
        id = saved_comment.id,
        file_path = saved_comment.file_path,
        modified_revision = saved_comment.modified_revision,
        original_revision = saved_comment.original_revision,
        start_line = start_line,
        end_line = end_line,
        text = saved_comment.text,
        created_at = saved_comment.created_at,
        created_order = saved_comment.created_order,
        code = saved_comment.code,
        extmark_id = nil,
      }
      comment.extmark_id = position.create_mark(session, file_state, comment)
      file_state.comments[id] = comment
    end
  end
end

---@param session StagedSession
---@param snapshot StagedSnapshot
function M.restore(session, snapshot)
  for file_key, file_state in pairs(session.files) do
    local saved_file = snapshot.files[file_key]
    restore_file(session, file_state, saved_file and saved_file.comments or {})
  end

  for file_key, saved_file in pairs(snapshot.files) do
    local file_state = session.files[file_key]
    if not file_state then
      file_state = vim.deepcopy(saved_file)
      file_state.comments = {}
      session.files[file_key] = file_state
      restore_file(session, file_state, saved_file.comments)
    end
  end
end

---@param session StagedSession
---@param snapshot StagedSnapshot
---@param action string
function M.record(session, snapshot, action)
  local history = get_history(session)
  anchor_missing_comments(session, snapshot)
  table.insert(history.undo, {
    action = action,
    snapshot = snapshot,
  })
  trim(session, history.undo)
  clear_entries(session, history.redo)
  history.redo = {}
end

---@param session StagedSession
---@param source StagedHistoryEntry[]
---@param destination StagedHistoryEntry[]
---@return boolean success
---@return string? action
local function restore_entry(session, source, destination)
  local entry = table.remove(source)
  if not entry then
    return false
  end

  local current = M.snapshot(session)
  M.restore(session, entry.snapshot)
  anchor_missing_comments(session, current)
  clear_snapshot_anchors(session, entry.snapshot)

  table.insert(destination, {
    action = entry.action,
    snapshot = current,
  })
  trim(session, destination)
  return true, entry.action
end

---@param session StagedSession
---@return boolean success
---@return string? action
function M.undo(session)
  local history = get_history(session)
  return restore_entry(session, history.undo, history.redo)
end

---@param session StagedSession
---@return boolean success
---@return string? action
function M.redo(session)
  local history = get_history(session)
  return restore_entry(session, history.redo, history.undo)
end

---@param session StagedSession
---@param file_key string Internal file-state key (see state.file_key)
---@param file_state StagedFileState
---@param new_bufnr integer
function M.migrate_anchors(session, file_key, file_state, new_bufnr)
  local new_file_state = {
    bufnr = new_bufnr,
    comments = file_state.comments,
  }
  local history = get_history(session)

  for _, entries in ipairs({ history.undo, history.redo }) do
    for _, entry in ipairs(entries) do
      local saved_file = entry.snapshot.files[file_key]
      if saved_file then
        saved_file.bufnr = new_bufnr
        for _, comment in ipairs(saved_file.comments) do
          if comment.history_extmark_id then
            local start_line, end_line = get_saved_lines(session, file_state, comment)
            position.delete_range_mark(
              session.history_ns_id,
              file_state,
              comment.history_extmark_id
            )
            comment.start_line = start_line
            comment.end_line = end_line
            comment.history_extmark_id = position.create_range_mark(
              session.history_ns_id,
              new_file_state,
              start_line,
              end_line
            )
          elseif not file_state.comments[comment.id] then
            comment.history_extmark_id = position.create_range_mark(
              session.history_ns_id,
              new_file_state,
              comment.start_line,
              comment.end_line
            )
          end
        end
      end
    end
  end
end

---Fold dormant history anchors in a disappearing buffer into their saved line
---numbers so a later undo restores against accurate positions.
---@param session StagedSession
---@param file_state StagedFileState
---@param bufnr integer
function M.capture_anchors(session, file_state, bufnr)
  local key = file_state_key(session, file_state)
  local history = get_history(session)
  for _, entries in ipairs({ history.undo, history.redo }) do
    for _, entry in ipairs(entries) do
      local saved_file = entry.snapshot.files[key]
      if saved_file then
        for _, comment in ipairs(saved_file.comments) do
          local live = file_state.comments[comment.id]
          if live then
            comment.start_line, comment.end_line = live.start_line, live.end_line
          else
            comment.start_line, comment.end_line = get_saved_lines(session, file_state, comment)
          end
          position.delete_range_mark(session.history_ns_id, file_state, comment.history_extmark_id)
          comment.history_extmark_id = nil
          comment.code = table.concat(
            vim.api.nvim_buf_get_lines(bufnr, comment.start_line - 1, comment.end_line, false),
            '\n'
          )
        end
      end
    end
  end
end

return M
