local M = {}

local config = require('staged.config')

---@param opts? table
function M.setup(opts)
  config.setup(opts)

  local state = require('staged.core.state')
  local sessions = state.get_all_sessions()
  for _, session in pairs(sessions) do
    state.clear_keymaps(session)
  end

  require('staged.ui.highlights').setup()
  for _, session in pairs(sessions) do
    require('staged.ui.sidebar').setup_keymaps(session)
  end

  local codediff = require('staged.integration.codediff')
  if codediff.is_available() then
    codediff.setup_autocmds()
  end

  M.setup_keymaps()

  vim.schedule(function()
    if not codediff.is_available() or not codediff.is_in_codediff() then
      return
    end

    local tabpage = vim.api.nvim_get_current_tabpage()
    if config.options.activation.mode == 'auto' or state.get_session(tabpage) then
      codediff.init_for_codediff(tabpage)
    end
  end)
end

---Bind keymaps to a specific buffer
---@param session StagedSession
---@param buf integer
local function bind_keymaps_to_buffer(session, buf)
  local state = require('staged.core.state')
  local km = config.options.keymaps
  local prefix = km.prefix

  state.clear_keymaps(session, buf)

  local function map(mode, lhs, callback, desc)
    state.set_keymap(session, buf, mode, lhs, callback, { desc = desc })
  end

  map('n', prefix .. km.add, function()
    M.add_comment_interactive()
  end, 'Add staged comment')

  map('v', prefix .. km.add, function()
    M.add_comment_visual()
  end, 'Add staged comment (selection)')

  map('n', prefix .. km.edit, function()
    M.edit_comment_at_cursor()
  end, 'Edit staged comment')

  map('n', prefix .. km.delete, function()
    M.delete_comment_at_cursor()
  end, 'Delete staged comment')

  map('n', prefix .. km.clear_all, function()
    M.clear_all()
  end, 'Clear all staged comments')

  map('n', prefix .. km.toggle_sidebar, function()
    M.toggle_sidebar()
  end, 'Toggle staged sidebar')

  map('n', prefix .. km.export_clipboard, function()
    require('staged.export').to_clipboard()
  end, 'Export to clipboard')

  map('n', prefix .. km.export_buffer, function()
    require('staged.export').to_buffer()
  end, 'Export to buffer')

  map('n', prefix .. km.export_file, function()
    require('staged.export').to_file()
  end, 'Export to file')

  map('n', km.next_comment, function()
    M.goto_next_comment()
  end, 'Next staged comment')

  map('n', km.prev_comment, function()
    M.goto_prev_comment()
  end, 'Previous staged comment')
end

---Try to bind keymaps for the current buffer if in codediff
---@param buf? integer
---@return boolean success
function M.try_bind_keymaps(buf)
  local codediff = require('staged.integration.codediff')
  if not codediff.is_in_codediff() then
    return false
  end

  local state = require('staged.core.state')
  local session = state.get_current_session()
  if not session then
    return false
  end

  buf = buf or vim.api.nvim_get_current_buf()
  local buf_path = vim.api.nvim_buf_get_name(buf)

  if session.current_file and buf_path == session.current_file then
    local file_state = state.get_current_file_state(session)
    if file_state and file_state.bufnr ~= buf then
      state.set_current_file(session, session.current_file, buf)
    end
    bind_keymaps_to_buffer(session, buf)
    return true
  end

  local file_state = state.get_current_file_state(session)
  if file_state and buf == file_state.bufnr then
    bind_keymaps_to_buffer(session, buf)
    return true
  end

  return false
end

---Bind keymaps for a staged session's modified buffer
---@param tabpage? integer
---@return boolean success
function M.bind_session_keymaps(tabpage)
  local state = require('staged.core.state')
  local session = state.get_session(tabpage or vim.api.nvim_get_current_tabpage())
  if not session then
    return false
  end

  local file_state = state.get_current_file_state(session)
  if not file_state or not vim.api.nvim_buf_is_valid(file_state.bufnr) then
    return false
  end

  bind_keymaps_to_buffer(session, file_state.bufnr)
  return true
end

---Setup keymaps for codediff buffers
function M.setup_keymaps()
  local group = vim.api.nvim_create_augroup('staged-keymaps', { clear = true })
  local refresh_versions = {}

  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter' }, {
    group = group,
    callback = function(args)
      M.try_bind_keymaps(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    callback = function(args)
      local state = require('staged.core.state')
      for _, session in pairs(state.get_all_sessions()) do
        state.clear_keymaps(session, args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'TextChangedP' }, {
    group = group,
    callback = function(args)
      local tabpage = vim.api.nvim_get_current_tabpage()
      local key = tabpage .. ':' .. args.buf
      local version = (refresh_versions[key] or 0) + 1
      refresh_versions[key] = version

      vim.defer_fn(function()
        if refresh_versions[key] ~= version then
          return
        end
        refresh_versions[key] = nil

        local state = require('staged.core.state')
        local session = state.get_session(tabpage)
        local file_state = session and state.get_current_file_state(session) or nil
        if not file_state or file_state.bufnr ~= args.buf then
          return
        end

        require('staged.ui.inline').render(session)
        require('staged.ui.sidebar').render(session)
      end, 50)
    end,
  })
end

---@return StagedSession|nil, StagedFileState|nil
local function get_modified_context()
  local state = require('staged.core.state')
  local session = state.get_current_session()
  if not session then
    vim.notify('No active staged session', vim.log.levels.WARN)
    return nil, nil
  end

  local file_state = state.get_current_file_state(session)
  if not file_state or vim.api.nvim_get_current_buf() ~= file_state.bufnr then
    vim.notify('Staged comments are only available in the modified buffer', vim.log.levels.WARN)
    return nil, nil
  end

  return session, file_state
end

---Add comment at current line
function M.add_comment_interactive()
  local session = get_modified_context()
  if not session then
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]

  require('staged.ui.input').open({ title = 'Add Comment' }, function(text)
    if text then
      require('staged.core.comments').add(line, line, text, session)
      require('staged.ui.inline').render(session)
      require('staged.ui.sidebar').maybe_auto_show(session)
      require('staged.ui.sidebar').render(session)
    end
  end)
end

---Add comment for visual selection
function M.add_comment_visual()
  local session = get_modified_context()
  if not session then
    return
  end

  local esc = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)
  vim.api.nvim_feedkeys(esc, 'x', false)

  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")

  require('staged.ui.input').open({ title = 'Add Comment' }, function(text)
    if text then
      require('staged.core.comments').add(start_line, end_line, text, session)
      require('staged.ui.inline').render(session)
      require('staged.ui.sidebar').maybe_auto_show(session)
      require('staged.ui.sidebar').render(session)
    end
  end)
end

---Edit comment at cursor
function M.edit_comment_at_cursor()
  local session = get_modified_context()
  if not session then
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local comment = require('staged.core.comments').get_at_line(line, session)

  if not comment then
    vim.notify('No comment at cursor', vim.log.levels.INFO)
    return
  end

  require('staged.ui.input').open(
    { title = 'Edit Comment', initial_text = comment.text },
    function(text)
      if text then
        require('staged.core.comments').edit(comment.id, text, session)
        require('staged.ui.sidebar').render(session)
      end
    end
  )
end

---Delete comment at cursor
function M.delete_comment_at_cursor()
  local session = get_modified_context()
  if not session then
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local comment = require('staged.core.comments').get_at_line(line, session)

  if not comment then
    vim.notify('No comment at cursor', vim.log.levels.INFO)
    return
  end

  require('staged.core.comments').delete(comment.id, session)
  require('staged.ui.inline').render(session)
  require('staged.ui.sidebar').render(session)
end

---Clear all comments
function M.clear_all()
  local state = require('staged.core.state')
  local session = state.get_current_session()
  if not session then
    return
  end

  require('staged.core.comments').clear_all(session)
  require('staged.ui.inline').clear_all(session)
  require('staged.ui.sidebar').render(session)
end

---Toggle sidebar
function M.toggle_sidebar()
  local state = require('staged.core.state')
  local session = state.get_current_session()
  if not session then
    return
  end

  require('staged.ui.sidebar').toggle(session)
end

---Enable staged for current tab
function M.enable()
  local codediff = require('staged.integration.codediff')
  local tabpage = vim.api.nvim_get_current_tabpage()
  local session = codediff.init_for_codediff(tabpage)
  if not session then
    vim.notify('No active codediff modified buffer', vim.log.levels.WARN)
  end
end

---Jump to next comment
function M.goto_next_comment()
  local session, file_state = get_modified_context()
  if not session then
    return
  end

  local comments = require('staged.core.comments')
  local position = require('staged.core.position')

  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local sorted = comments.get_sorted(session)

  for _, comment in ipairs(sorted) do
    local start_line = position.get_current_lines(session, file_state, comment)
    if start_line > current_line then
      vim.api.nvim_win_set_cursor(0, { start_line, 0 })
      return
    end
  end

  -- Wrap to first
  if #sorted > 0 then
    local start_line = position.get_current_lines(session, file_state, sorted[1])
    vim.api.nvim_win_set_cursor(0, { start_line, 0 })
  end
end

---Jump to previous comment
function M.goto_prev_comment()
  local session, file_state = get_modified_context()
  if not session then
    return
  end

  local comments = require('staged.core.comments')
  local position = require('staged.core.position')

  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local sorted = comments.get_sorted(session)

  for i = #sorted, 1, -1 do
    local comment = sorted[i]
    local start_line = position.get_current_lines(session, file_state, comment)
    if start_line < current_line then
      vim.api.nvim_win_set_cursor(0, { start_line, 0 })
      return
    end
  end

  -- Wrap to last
  if #sorted > 0 then
    local start_line = position.get_current_lines(session, file_state, sorted[#sorted])
    vim.api.nvim_win_set_cursor(0, { start_line, 0 })
  end
end

-- Re-export useful functions
M.add_comment = function(...)
  return require('staged.core.comments').add(...)
end

M.get_comments = function()
  return require('staged.core.comments').get_sorted()
end

return M
