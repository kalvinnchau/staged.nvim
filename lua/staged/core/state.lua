local M = {}

local WORKING = 'WORKING'

---Canonical revision string (nil/empty collapse to WORKING)
---@param revision? string
---@return string
function M.normalize_revision(revision)
  if revision == nil or revision == '' or revision == WORKING then
    return WORKING
  end
  return revision
end

---@type table<integer, StagedSession> Sessions indexed by tabpage ID
local sessions = {}

---@type table<integer, boolean> Tabpages currently being torn down
local destroying = {}

---@class StagedManagedKeymap
---@field owners table<StagedSession, boolean>
---@field previous? table
---@field rhs string|function

---@type table<integer, table<string, StagedManagedKeymap>>
local managed_keymaps = {}

---@param tabpage integer Tabpage ID
---@return StagedSession
function M.create_session(tabpage)
  if sessions[tabpage] then
    M.destroy_session(tabpage)
  end

  local ns_id = vim.api.nvim_create_namespace('staged-' .. tabpage)
  local indicator_ns_id = vim.api.nvim_create_namespace('staged-indicators-' .. tabpage)
  local history_ns_id = vim.api.nvim_create_namespace('staged-history-' .. tabpage)

  ---@type StagedSession
  local session = {
    tabpage = tabpage,
    active = true,
    root = vim.fn.getcwd(),
    files = {},
    current_file = nil,
    sidebar_bufnr = nil,
    sidebar_winid = nil,
    visible = false,
    ns_id = ns_id,
    indicator_ns_id = indicator_ns_id,
    history_ns_id = history_ns_id,
    keymaps = {},
    history = {
      undo = {},
      redo = {},
    },
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

---@param tabpage integer
---@return boolean
function M.is_destroying(tabpage)
  return destroying[tabpage] == true
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
  if type(rhs) == 'string' and mapping.sid and mapping.sid > 0 then
    rhs = rhs:gsub('<[sS][iI][dD]>', '<SNR>' .. mapping.sid .. '_')
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

---Compute the internal file-state key for a review identity.
---Keyed by path + modified revision only (NUL-delimited to avoid collisions
---with real '#' filenames); the working tree always keeps the bare path.
---@param file_path string Absolute modified-side path
---@param context? StagedReviewContext Review context carrying revisions
---@return string
function M.file_key(file_path, context)
  local modified = M.normalize_revision(context and context.modified_revision)
  if modified == WORKING then
    return file_path
  end
  return file_path .. '\0' .. modified
end

---Deactivate the current modified side while retaining its review comments.
---@param session StagedSession
function M.deactivate_current_file(session)
  local file_state = M.get_current_file_state(session)
  if file_state then
    M.clear_keymaps(session, file_state.bufnr)
    if vim.api.nvim_buf_is_valid(file_state.bufnr) then
      vim.api.nvim_buf_clear_namespace(file_state.bufnr, session.indicator_ns_id, 0, -1)
    end
  end
  session.current_file = nil
end

---Set the current file for a session, creating file state if needed
---@param session StagedSession
---@param file_path string
---@param bufnr integer
---@param context? StagedReviewContext Review context (modified_revision, original_revision)
function M.set_current_file(session, file_path, bufnr, context)
  local key = M.file_key(file_path, context)
  local previous_key = session.current_file
  local previous_state = previous_key and session.files[previous_key] or nil

  if previous_state and (previous_key ~= key or previous_state.bufnr ~= bufnr) then
    M.deactivate_current_file(session)
  end

  session.current_file = key

  local file_state = session.files[key]
  if not file_state then
    ---@type StagedFileState
    file_state = {
      bufnr = bufnr,
      comments = {},
      file_path = file_path,
      modified_revision = M.normalize_revision(context and context.modified_revision),
      original_revision = context and context.original_revision or nil,
    }
    session.files[key] = file_state
    return
  end

  if context then
    file_state.original_revision = context.original_revision
  end
  if file_state.bufnr == bufnr and not file_state.needs_marks then
    return
  end

  local position = require('staged.core.position')
  for _, comment in pairs(file_state.comments) do
    local start_line, end_line = position.get_current_lines(session, file_state, comment)
    position.delete_mark(session, file_state, comment)
    comment.start_line = start_line
    comment.end_line = end_line
  end

  require('staged.core.history').migrate_anchors(session, key, file_state, bufnr)
  file_state.bufnr = bufnr
  file_state.needs_marks = not vim.api.nvim_buf_is_loaded(bufnr)
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

---Get file state by internal key (see state.file_key)
---@param session StagedSession
---@param key string Internal file-state key
---@return StagedFileState|nil
function M.get_file_state(session, key)
  return session.files[key]
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
  local file_state = M.get_current_file_state(session)
  return file_state and file_state.file_path or nil
end

---@param tabpage integer
function M.destroy_session(tabpage)
  if destroying[tabpage] then
    return
  end

  local session = sessions[tabpage]
  if not session then
    return
  end

  destroying[tabpage] = true
  sessions[tabpage] = nil
  session.active = false

  local ok, err = pcall(function()
    M.clear_keymaps(session)

    for _, file_state in pairs(session.files) do
      if vim.api.nvim_buf_is_valid(file_state.bufnr) then
        vim.api.nvim_buf_clear_namespace(file_state.bufnr, session.ns_id, 0, -1)
        vim.api.nvim_buf_clear_namespace(file_state.bufnr, session.indicator_ns_id, 0, -1)
        vim.api.nvim_buf_clear_namespace(file_state.bufnr, session.history_ns_id, 0, -1)
      end
    end

    if session.sidebar_bufnr and vim.api.nvim_buf_is_valid(session.sidebar_bufnr) then
      vim.api.nvim_buf_delete(session.sidebar_bufnr, { force = true })
    end
  end)

  destroying[tabpage] = nil
  if not ok then
    error(err, 0)
  end
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

---Capture live comment positions and code snippets from a buffer that is
---about to be unloaded/wiped, so exports and later undos survive the loss of
---its extmarks. Dormant history anchors (comments absent from a file state,
---e.g. after an undo) are folded into their saved start/end lines too.
---Called by setup's unload/wipe hooks while the buffer is still readable.
---@param session StagedSession
---@param bufnr integer
function M.capture_buffer(session, bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end
  local position = require('staged.core.position')
  local history = require('staged.core.history')

  for _, file_state in pairs(session.files) do
    if file_state.bufnr == bufnr then
      file_state.needs_marks = true
      for _, comment in pairs(file_state.comments) do
        local start_line, end_line = position.get_current_lines(session, file_state, comment)
        comment.start_line = start_line
        comment.end_line = end_line
        if vim.api.nvim_buf_is_loaded(bufnr) then
          local ok, lines =
            pcall(vim.api.nvim_buf_get_lines, bufnr, start_line - 1, end_line, false)
          if ok and type(lines) == 'table' then
            local snippet = table.concat(lines, '\n')
            comment.code = snippet
          end
        end
        position.delete_mark(session, file_state, comment)
        comment.extmark_id = nil
      end

      history.capture_anchors(session, file_state, bufnr)
    end
  end
end

return M
