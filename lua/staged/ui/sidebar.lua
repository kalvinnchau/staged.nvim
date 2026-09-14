local M = {}

local state = require('staged.core.state')
local config = require('staged.config')
local comments = require('staged.core.comments')
local position = require('staged.core.position')

local ns_highlights = vim.api.nvim_create_namespace('staged-sidebar-highlights')

---@class SidebarLine
---@field type 'file'|'range'|'comment'|'empty'
---@field comment_id? string
---@field file_key? string Internal file-state key (see state.file_key)

---@type table<integer, SidebarLine[]> Line metadata per sidebar buffer
local line_data = {}

---@param session StagedSession
---@return boolean
local function session_is_active(session)
  return state.get_session(session.tabpage) == session
end

---@param session StagedSession
---@param file_state StagedFileState
---@param comment StagedComment
---@return boolean
local function comment_is_active(session, file_state, comment)
  return session_is_active(session) and file_state.comments[comment.id] == comment
end

---@param session StagedSession
---@return boolean
local function is_visible(session)
  return session.sidebar_winid ~= nil and vim.api.nvim_win_is_valid(session.sidebar_winid)
end

---Create sidebar buffer
---@param session StagedSession
---@return integer bufnr
local function create_buffer(session)
  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'staged-sidebar'
  vim.api.nvim_buf_set_name(buf, 'staged://comments/' .. session.tabpage)

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = function()
      line_data[buf] = nil
      if session.sidebar_bufnr == buf then
        session.sidebar_bufnr = nil
        session.sidebar_winid = nil
        session.visible = false
      end
    end,
  })

  return buf
end

---Find a compatible visible left-side codediff panel (explorer/history) that the
---sidebar can nest below. Read-only: codediff state is never touched.
---@param session StagedSession
---@return integer|nil panel_win
local function find_left_panel(session)
  local view = require('staged.integration.codediff').get_panel_view(session.tabpage)
  local winid = type(view) == 'table' and view.winid or nil
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return nil
  end
  if view.is_hidden then
    return nil
  end

  local ok, win_config = pcall(vim.api.nvim_win_get_config, winid)
  if not ok then
    return nil
  end
  -- Only a plain, currently visible left split is a compatible host; right and
  -- bottom panels (and floats) fall back to a top-level side split.
  if win_config.relative ~= '' or win_config.external then
    return nil
  end
  if win_config.split ~= 'left' then
    return nil
  end
  return winid
end

---Apply sidebar window options. Diff windows share scroll/cursor binding and
---statuscolumn state; the sidebar must opt out of all of them so it never
---disturbs diff scrolling.
---@param win integer
---@param vertical boolean True for a full-height side split, false for a row
local function apply_window_options(win, vertical)
  local wo = vim.wo[win]
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = 'no'
  wo.foldcolumn = '0'
  wo.wrap = true
  wo.spell = false
  wo.cursorline = true
  wo.scrollbind = false
  wo.cursorbind = false
  wo.statuscolumn = ''
  if vertical then
    wo.winfixwidth = true
  else
    wo.winfixheight = true
  end
end

---@param session StagedSession
---@param buf integer
---@return integer winid
local function create_window(session, buf)
  local pos = config.options.sidebar.position
  local panel_win = pos == 'left' and find_left_panel(session) or nil
  local opts
  if panel_win then
    opts = { split = 'below', win = panel_win, height = config.options.sidebar.height }
  else
    opts = { split = pos, win = -1, width = config.options.sidebar.width }
  end
  local win = vim.api.nvim_open_win(buf, false, opts)
  apply_window_options(win, panel_win == nil)
  return win
end

---Real path for display, never the encoded file-state key
---@param file_state StagedFileState|nil
---@param fallback_key string
---@return string
local function display_name(file_state, fallback_key)
  local path = file_state and file_state.file_path or nil
  if type(path) ~= 'string' or path == '' then
    path = fallback_key
  end
  local name = vim.fn.fnamemodify(path, ':~:.')
  if name == '' then
    name = '[buffer]'
  end
  return name
end

---Short revision suffix for a file header; empty for the working tree
---@param file_state StagedFileState|nil
---@return string display, string sort_key
local function revision_label(file_state)
  local rev = state.normalize_revision(file_state and file_state.modified_revision)
  if rev == 'WORKING' then
    return '', ''
  end
  return ' @' .. (rev:len() > 12 and rev:sub(1, 8) or rev), rev
end

---Render sidebar contents
---@param session StagedSession
function M.render(session)
  if not session.sidebar_bufnr or not vim.api.nvim_buf_is_valid(session.sidebar_bufnr) then
    return
  end

  local grouped = comments.get_all_grouped(session)
  local lines = {}
  local hl_ranges = {}
  line_data[session.sidebar_bufnr] = {}
  local data = line_data[session.sidebar_bufnr]

  -- Title
  table.insert(lines, string.format('Comments (%d):', state.total_comment_count(session)))
  table.insert(data, { type = 'empty' })

  -- Sort by display path (then revision) so real files group together even
  -- when multiple review revisions of one path exist
  local files = {}
  for key in pairs(grouped) do
    local file_state = state.get_file_state(session, key)
    local label, revision = revision_label(file_state)
    table.insert(files, {
      key = key,
      state = file_state,
      name = display_name(file_state, key),
      label = label,
      revision = revision,
    })
  end
  table.sort(files, function(a, b)
    if a.name ~= b.name then
      return a.name < b.name
    end
    if a.revision ~= b.revision then
      return a.revision < b.revision
    end
    return a.key < b.key
  end)

  for _, file in ipairs(files) do
    local file_key, file_state = file.key, file.state
    local file_comments = grouped[file_key]
    local filename, label = file.name, file.label
    table.insert(lines, '')
    table.insert(data, { type = 'empty' })
    table.insert(lines, ' ' .. filename .. label .. ':')
    table.insert(hl_ranges, { #lines, 1, #filename, 'StagedSidebarFile' })
    if label ~= '' then
      table.insert(hl_ranges, { #lines, 1 + #filename, #label, 'StagedSidebarLineNr' })
    end
    table.insert(data, { type = 'file', file_key = file_key })

    for _, comment in ipairs(file_comments) do
      local start_line, end_line = comment.start_line, comment.end_line
      if file_state then
        start_line, end_line = position.get_current_lines(session, file_state, comment)
      end

      -- Line range with comment on same line if short enough
      local range_text
      if start_line == end_line then
        range_text = string.format('l%d', start_line)
      else
        range_text = string.format('l%d-%d', start_line, end_line)
      end

      -- Get first line of comment
      local comment_lines = vim.split(comment.text, '\n')
      local first_line = comment_lines[1] or ''

      -- Format: "  l5: comment text"
      local full_line = '  ' .. range_text .. ': ' .. first_line
      table.insert(lines, full_line)
      table.insert(hl_ranges, { #lines, 2, #range_text, 'StagedSidebarLineNr' })
      if first_line ~= '' then
        table.insert(
          hl_ranges,
          { #lines, 2 + #range_text + 2, #first_line, 'StagedSidebarComment' }
        )
      end
      table.insert(data, { type = 'range', comment_id = comment.id, file_key = file_key })

      -- Additional comment lines (indented to align with first line)
      local indent = string.rep(' ', 2 + #range_text + 2)
      for i = 2, #comment_lines do
        table.insert(lines, indent .. comment_lines[i])
        if comment_lines[i] ~= '' then
          table.insert(hl_ranges, { #lines, #indent, #comment_lines[i], 'StagedSidebarComment' })
        end
        table.insert(data, {
          type = 'comment',
          comment_id = comment.id,
          file_key = file_key,
        })
      end
    end
  end

  -- Set buffer contents
  vim.bo[session.sidebar_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(session.sidebar_bufnr, 0, -1, false, lines)
  vim.bo[session.sidebar_bufnr].modifiable = false

  -- Apply highlights using extmarks (0.10+)
  vim.api.nvim_buf_clear_namespace(session.sidebar_bufnr, ns_highlights, 0, -1)
  for _, hl in ipairs(hl_ranges) do
    local line_idx, col_start, col_end, hl_group = hl[1], hl[2], hl[3], hl[4]
    vim.api.nvim_buf_set_extmark(session.sidebar_bufnr, ns_highlights, line_idx - 1, col_start, {
      end_col = col_start + col_end,
      hl_group = hl_group,
    })
  end
end

---Setup keymaps for sidebar buffer
---@param session StagedSession
function M.setup_keymaps(session)
  local buf = session.sidebar_bufnr
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local km = config.options.keymaps
  local prefix = km.prefix
  state.clear_keymaps(session, buf)

  local mapped = {}
  local function mapping_key(lhs)
    return vim.api.nvim_replace_termcodes(lhs, true, true, true)
  end

  local function map(lhs, callback, desc)
    state.set_keymap(session, buf, 'n', lhs, callback, { desc = desc })
    mapped[mapping_key(lhs)] = true
  end

  local function map_new(lhs, callback, desc)
    if not mapped[mapping_key(lhs)] then
      map(lhs, callback, desc)
    end
  end

  map('<CR>', function()
    M.goto_comment(session)
  end, 'Go to comment')

  map('e', function()
    M.edit_comment(session)
  end, 'Edit comment')

  map('d', function()
    M.delete_comment(session)
  end, 'Delete comment')

  map('q', function()
    M.hide(session)
  end, 'Close sidebar')

  map(prefix .. km.export_clipboard, function()
    require('staged.export').to_clipboard()
  end, 'Export to clipboard')

  map(prefix .. km.export_buffer, function()
    require('staged.export').to_buffer()
  end, 'Export to buffer')

  map(prefix .. km.export_file, function()
    require('staged.export').to_file()
  end, 'Export to file')

  map(prefix .. km.clear_all, function()
    require('staged.core.comments').clear_all(session)
    require('staged.ui.inline').clear_all(session)
    M.render(session)
  end, 'Clear all comments')

  map_new(prefix .. km.undo, function()
    require('staged').undo()
  end, 'Undo comment change')

  map_new(prefix .. km.redo, function()
    require('staged').redo()
  end, 'Redo comment change')
end

---Show sidebar
---@param session StagedSession
function M.show(session)
  if is_visible(session) then
    return
  end

  session.sidebar_winid = nil
  session.visible = false

  if not session.sidebar_bufnr or not vim.api.nvim_buf_is_valid(session.sidebar_bufnr) then
    session.sidebar_bufnr = create_buffer(session)
    M.setup_keymaps(session)
  end

  session.sidebar_winid = create_window(session, session.sidebar_bufnr)
  vim.api.nvim_win_set_buf(session.sidebar_winid, session.sidebar_bufnr)

  session.visible = true
  local winid = session.sidebar_winid
  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(winid),
    once = true,
    callback = function()
      if session.sidebar_winid == winid then
        session.sidebar_winid = nil
        session.visible = false
      end
    end,
  })
  M.render(session)
end

---Hide sidebar
---@param session StagedSession
function M.hide(session)
  if is_visible(session) then
    vim.api.nvim_win_close(session.sidebar_winid, true)
  end
  session.sidebar_winid = nil
  session.visible = false
end

---Toggle sidebar visibility
---@param session StagedSession
function M.toggle(session)
  if is_visible(session) then
    M.hide(session)
  else
    M.show(session)
  end
end

---Resolve the sidebar entry under the cursor
---@param session StagedSession
---@return SidebarLine|nil
local function entry_at_cursor(session)
  if not session.sidebar_bufnr then
    return nil
  end
  local data = line_data[session.sidebar_bufnr]
  if not data then
    return nil
  end
  return data[vim.api.nvim_win_get_cursor(0)[1]]
end

---Find a visible window in the session tabpage displaying the file's buffer,
---preferring the codediff modified-side window. Buffer identity is the
---revision identity: each review revision owns its own buffer.
---@param session StagedSession
---@param file_state StagedFileState
---@return integer|nil winid
local function find_file_window(session, file_state)
  local buf = file_state.bufnr
  if not buf or not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return nil
  end
  if not vim.api.nvim_tabpage_is_valid(session.tabpage) then
    return nil
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(session.tabpage)) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      local ok, win_config = pcall(vim.api.nvim_win_get_config, win)
      if ok and win_config.relative == '' and not win_config.external then
        return win
      end
    end
  end
  return nil
end

---Place the cursor on the comment target and open compact-mode folds covering
---it so the commented line is actually visible.
---@param session StagedSession
---@param file_state StagedFileState
---@param comment StagedComment
---@param win integer
local function reveal_in_window(session, file_state, comment, win)
  local start_line = position.get_current_lines(session, file_state, comment)
  pcall(vim.api.nvim_win_set_cursor, win, { start_line, 0 })

  vim.api.nvim_win_call(win, function()
    vim.cmd('normal! zv')
  end)
end

---Jump to comment under cursor
---@param session StagedSession
function M.goto_comment(session)
  local entry = entry_at_cursor(session)
  if not entry or not entry.comment_id or not entry.file_key then
    return
  end

  local file_state = state.get_file_state(session, entry.file_key)
  if not file_state then
    return
  end

  local comment = file_state.comments[entry.comment_id]
  if not comment then
    return
  end

  if not vim.api.nvim_tabpage_is_valid(session.tabpage) then
    return
  end

  -- Real codediff session: always navigate through the adapter's cancellable
  -- jump_to_comment (it owns modified-window focus, revision reopen, and fold
  -- reveal via zv). Buffer-identity lookup below is only for standalone UIs.
  local codediff = require('staged.integration.codediff')
  if codediff.get_codediff_session(session.tabpage) then
    codediff.jump_to_comment(session, file_state, comment)
    return
  end

  -- Standalone fallback (no codediff): jump to the window showing this
  -- revision's buffer.
  local win = find_file_window(session, file_state)
  if win then
    vim.api.nvim_set_current_win(win)
    reveal_in_window(session, file_state, comment, win)
    return
  end

  vim.notify('Comment file is not open in this codediff', vim.log.levels.INFO)
end

---Edit comment under cursor
---@param session StagedSession
function M.edit_comment(session)
  local entry = entry_at_cursor(session)
  if not entry or not entry.comment_id or not entry.file_key then
    return
  end

  local file_state = state.get_file_state(session, entry.file_key)
  if not file_state then
    return
  end

  local comment = file_state.comments[entry.comment_id]
  if not comment then
    return
  end

  local input = require('staged.ui.input')
  input.open({ title = 'Edit Comment', initial_text = comment.text }, function(text)
    if
      text
      and comment_is_active(session, file_state, comment)
      and comments.edit(entry.comment_id, text, session)
      and session_is_active(session)
    then
      M.render(session)
    end
  end)
end

---Delete comment under cursor
---@param session StagedSession
function M.delete_comment(session)
  local entry = entry_at_cursor(session)
  if not entry or not entry.comment_id then
    return
  end

  if
    session_is_active(session)
    and comments.delete(entry.comment_id, session)
    and session_is_active(session)
  then
    M.render(session)
    if entry.file_key == session.current_file then
      require('staged.ui.inline').render(session)
    end
  end
end

---Auto-show sidebar if configured and this is first comment
---@param session StagedSession
function M.maybe_auto_show(session)
  if
    config.options.sidebar.auto_show
    and state.total_comment_count(session) == 1
    and not is_visible(session)
  then
    M.show(session)
  end
end

return M
