local M = {}

local state = require('staged.core.state')
local config = require('staged.config')
local comments = require('staged.core.comments')
local position = require('staged.core.position')

local ns_highlights = vim.api.nvim_create_namespace('staged-sidebar-highlights')

---@class SidebarLine
---@field type 'file'|'range'|'comment'|'empty'
---@field comment_id? string
---@field file_path? string

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

---Find the codediff explorer window
---@param session StagedSession
---@return integer|nil winid
local function find_explorer_window(session)
  local codediff = require('staged.integration.codediff')
  local codediff_session = codediff.get_codediff_session(session.tabpage)
  if codediff_session and codediff_session.explorer and codediff_session.explorer.winid then
    local winid = codediff_session.explorer.winid
    if vim.api.nvim_win_is_valid(winid) then
      return winid
    end
  end
  return nil
end

---Create sidebar window
---@param session StagedSession
---@return integer winid
local function create_window(session)
  local pos = config.options.sidebar.position
  local width = config.options.sidebar.width
  local height = config.options.sidebar.height or 15

  -- Save current window to restore later
  local current_win = vim.api.nvim_get_current_win()

  -- Try to split below the codediff explorer if position is 'left'
  local explorer_win = nil
  if pos == 'left' then
    explorer_win = find_explorer_window(session)
  end

  if explorer_win then
    -- Split below the explorer window
    vim.api.nvim_set_current_win(explorer_win)
    vim.cmd('belowright split')
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_height(win, height)

    -- Set window options
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = 'no'
    vim.wo[win].foldcolumn = '0'
    vim.wo[win].wrap = true
    vim.wo[win].winfixheight = true
    vim.wo[win].cursorline = true

    -- Return to original window
    vim.api.nvim_set_current_win(current_win)
    return win
  end

  -- Fallback: create vertical split
  if pos == 'right' then
    vim.cmd('botright vsplit')
  else
    vim.cmd('topleft vsplit')
  end

  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(win, width)

  -- Set window options
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].foldcolumn = '0'
  vim.wo[win].wrap = true
  vim.wo[win].winfixwidth = true
  vim.wo[win].cursorline = true

  -- Return to original window
  vim.api.nvim_set_current_win(current_win)

  return win
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

  -- Sort file paths for consistent ordering
  local file_paths = {}
  for file_path in pairs(grouped) do
    table.insert(file_paths, file_path)
  end
  table.sort(file_paths)

  for _, file_path in ipairs(file_paths) do
    local file_comments = grouped[file_path]
    local file_state = state.get_file_state(session, file_path)

    -- Filename header
    local filename = vim.fn.fnamemodify(file_path, ':~:.')
    if filename == '' then
      filename = '[buffer]'
    end
    table.insert(lines, '')
    table.insert(data, { type = 'empty' })
    table.insert(lines, ' ' .. filename .. ':')
    table.insert(hl_ranges, { #lines, 1, #filename, 'StagedSidebarFile' })
    table.insert(data, { type = 'file', file_path = file_path })

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
      table.insert(data, { type = 'range', comment_id = comment.id, file_path = file_path })

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
          file_path = file_path,
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

  local function map(lhs, callback, desc)
    state.set_keymap(session, buf, 'n', lhs, callback, { desc = desc })
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

  map(prefix .. km.undo, function()
    require('staged').undo()
  end, 'Undo comment change')

  map(prefix .. km.redo, function()
    require('staged').redo()
  end, 'Redo comment change')

  map(prefix .. km.clear_all, function()
    require('staged.core.comments').clear_all(session)
    require('staged.ui.inline').clear_all(session)
    M.render(session)
  end, 'Clear all comments')
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

  session.sidebar_winid = create_window(session)
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

---Jump to comment under cursor
---@param session StagedSession
function M.goto_comment(session)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local data = line_data[session.sidebar_bufnr]

  if not data or not data[cursor_line] then
    return
  end

  local entry = data[cursor_line]
  if not entry.comment_id or not entry.file_path then
    return
  end

  -- Get the file state for this comment's file
  local file_state = state.get_file_state(session, entry.file_path)
  if not file_state then
    return
  end

  local comment = file_state.comments[entry.comment_id]
  if not comment then
    return
  end
  local line = position.get_current_lines(session, file_state, comment)

  if not vim.api.nvim_tabpage_is_valid(session.tabpage) then
    return
  end

  local wins = vim.api.nvim_tabpage_list_wins(session.tabpage)
  for _, win in ipairs(wins) do
    local buf = vim.api.nvim_win_get_buf(win)
    if buf == file_state.bufnr then
      vim.api.nvim_set_current_win(win)
      vim.api.nvim_win_set_cursor(win, { line, 0 })
      return
    end
  end

  vim.notify('Comment file is not open in this codediff', vim.log.levels.INFO)
end

---Edit comment under cursor
---@param session StagedSession
function M.edit_comment(session)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local data = line_data[session.sidebar_bufnr]

  if not data or not data[cursor_line] then
    return
  end

  local entry = data[cursor_line]
  if not entry.comment_id or not entry.file_path then
    return
  end

  local file_state = state.get_file_state(session, entry.file_path)
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
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local data = line_data[session.sidebar_bufnr]

  if not data or not data[cursor_line] then
    return
  end

  local entry = data[cursor_line]
  if not entry.comment_id then
    return
  end

  if
    session_is_active(session)
    and comments.delete(entry.comment_id, session)
    and session_is_active(session)
  then
    M.render(session)
    if entry.file_path == session.current_file then
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
