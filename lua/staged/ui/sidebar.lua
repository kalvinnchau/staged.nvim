local M = {}

local state = require('staged.core.state')
local config = require('staged.config')
local comments = require('staged.core.comments')
local position = require('staged.core.position')

---@class SidebarLine
---@field type 'file'|'range'|'comment'|'empty'
---@field comment_id? string
---@field line_nr? integer
---@field file_path? string

---@type table<integer, SidebarLine[]> Line metadata per sidebar buffer
local line_data = {}

---Create sidebar buffer
---@param session StagedSession
---@return integer bufnr
local function create_buffer(session)
  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'staged-sidebar'
  vim.api.nvim_buf_set_name(buf, 'Staged Comments')

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

  local grouped = comments.get_all_grouped()
  local lines = {}
  local hl_ranges = {}
  line_data[session.sidebar_bufnr] = {}
  local data = line_data[session.sidebar_bufnr]

  -- Title
  table.insert(lines, 'Comments:')
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
    local filename = vim.fn.fnamemodify(file_path, ':t')
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
      table.insert(
        data,
        { type = 'range', comment_id = comment.id, line_nr = start_line, file_path = file_path }
      )

      -- Additional comment lines (indented to align with first line)
      local indent = string.rep(' ', 2 + #range_text + 2)
      for i = 2, #comment_lines do
        table.insert(lines, indent .. comment_lines[i])
        table.insert(data, { type = 'comment', comment_id = comment.id, file_path = file_path })
      end
    end
  end

  -- Set buffer contents
  vim.bo[session.sidebar_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(session.sidebar_bufnr, 0, -1, false, lines)
  vim.bo[session.sidebar_bufnr].modifiable = false

  -- Apply highlights using extmarks (0.10+)
  local ns = vim.api.nvim_create_namespace('staged-sidebar-hl')
  vim.api.nvim_buf_clear_namespace(session.sidebar_bufnr, ns, 0, -1)
  for _, hl in ipairs(hl_ranges) do
    local line_idx, col_start, col_end, hl_group = hl[1], hl[2], hl[3], hl[4]
    vim.api.nvim_buf_set_extmark(session.sidebar_bufnr, ns, line_idx - 1, col_start, {
      end_col = col_start + col_end,
      hl_group = hl_group,
    })
  end
end

---Setup keymaps for sidebar buffer
---@param session StagedSession
local function setup_keymaps(session)
  local buf = session.sidebar_bufnr
  local km = config.options.keymaps
  local prefix = km.prefix

  -- Jump to comment location
  vim.keymap.set('n', '<CR>', function()
    M.goto_comment(session)
  end, { buffer = buf, desc = 'Go to comment' })

  -- Edit comment
  vim.keymap.set('n', 'e', function()
    M.edit_comment(session)
  end, { buffer = buf, desc = 'Edit comment' })

  -- Delete comment
  vim.keymap.set('n', 'd', function()
    M.delete_comment(session)
  end, { buffer = buf, desc = 'Delete comment' })

  -- Close sidebar
  vim.keymap.set('n', 'q', function()
    M.hide(session)
  end, { buffer = buf, desc = 'Close sidebar' })

  -- Export keymaps (same as main buffer)
  vim.keymap.set('n', prefix .. km.export_clipboard, function()
    require('staged.export').to_clipboard()
  end, { buffer = buf, desc = 'Export to clipboard' })

  vim.keymap.set('n', prefix .. km.export_buffer, function()
    require('staged.export').to_buffer()
  end, { buffer = buf, desc = 'Export to buffer' })

  vim.keymap.set('n', prefix .. km.export_file, function()
    require('staged.export').to_file()
  end, { buffer = buf, desc = 'Export to file' })

  -- Clear all
  vim.keymap.set('n', prefix .. km.clear_all, function()
    require('staged.core.comments').clear_all()
    require('staged.ui.inline').render(session)
    M.render(session)
  end, { buffer = buf, desc = 'Clear all comments' })
end

---Show sidebar
---@param session StagedSession
function M.show(session)
  if session.visible then
    return
  end

  -- Create buffer if needed
  if not session.sidebar_bufnr or not vim.api.nvim_buf_is_valid(session.sidebar_bufnr) then
    session.sidebar_bufnr = create_buffer(session)
    setup_keymaps(session)
  end

  -- Create window
  session.sidebar_winid = create_window(session)
  vim.api.nvim_win_set_buf(session.sidebar_winid, session.sidebar_bufnr)

  session.visible = true
  M.render(session)
end

---Hide sidebar
---@param session StagedSession
function M.hide(session)
  if not session.visible then
    return
  end

  if session.sidebar_winid and vim.api.nvim_win_is_valid(session.sidebar_winid) then
    vim.api.nvim_win_close(session.sidebar_winid, true)
  end

  session.sidebar_winid = nil
  session.visible = false
end

---Toggle sidebar visibility
---@param session StagedSession
function M.toggle(session)
  if session.visible then
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
  if not entry.line_nr or not entry.file_path then
    return
  end

  -- Get the file state for this comment's file
  local file_state = state.get_file_state(session, entry.file_path)
  if not file_state then
    return
  end

  -- Find the window showing this buffer
  local wins = vim.api.nvim_tabpage_list_wins(session.tabpage)
  for _, win in ipairs(wins) do
    local buf = vim.api.nvim_win_get_buf(win)
    if buf == file_state.bufnr then
      vim.api.nvim_set_current_win(win)
      vim.api.nvim_win_set_cursor(win, { entry.line_nr, 0 })
      return
    end
  end
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
    if text then
      comments.edit(entry.comment_id, text)
      M.render(session)
      require('staged.ui.inline').render(session)
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

  comments.delete(entry.comment_id)
  M.render(session)
  require('staged.ui.inline').render(session)
end

---Auto-show sidebar if configured and this is first comment
---@param session StagedSession
function M.maybe_auto_show(session)
  if config.options.sidebar.auto_show and comments.count() == 1 and not session.visible then
    M.show(session)
  end
end

return M
