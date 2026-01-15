local M = {}

local config = require('staged.config')

---@param opts? table
function M.setup(opts)
  config.setup(opts)

  -- Setup highlights
  require('staged.ui.highlights').setup()

  -- Setup codediff integration
  local codediff = require('staged.integration.codediff')
  if codediff.is_available() then
    codediff.setup_autocmds()
  end

  -- Setup keymaps (only when in codediff buffer)
  M.setup_keymaps()

  -- Immediately check if we're already in a codediff tab
  -- (handles case where plugin loads after entering the tab)
  vim.schedule(function()
    if codediff.is_available() and codediff.is_in_codediff() then
      local tabpage = vim.api.nvim_get_current_tabpage()
      codediff.init_for_codediff(tabpage)
      M.try_bind_keymaps()
    end
  end)
end

---Bind keymaps to a specific buffer
---@param buf integer
local function bind_keymaps_to_buffer(buf)
  local km = config.options.keymaps
  local prefix = km.prefix

  -- Add comment (normal mode)
  vim.keymap.set('n', prefix .. km.add, function()
    M.add_comment_interactive()
  end, { buffer = buf, desc = 'Add staged comment' })

  -- Add comment (visual mode)
  vim.keymap.set('v', prefix .. km.add, function()
    M.add_comment_visual()
  end, { buffer = buf, desc = 'Add staged comment (selection)' })

  -- Edit comment
  vim.keymap.set('n', prefix .. km.edit, function()
    M.edit_comment_at_cursor()
  end, { buffer = buf, desc = 'Edit staged comment' })

  -- Delete comment
  vim.keymap.set('n', prefix .. km.delete, function()
    M.delete_comment_at_cursor()
  end, { buffer = buf, desc = 'Delete staged comment' })

  -- Clear all
  vim.keymap.set('n', prefix .. km.clear_all, function()
    M.clear_all()
  end, { buffer = buf, desc = 'Clear all staged comments' })

  -- Toggle sidebar
  vim.keymap.set('n', prefix .. km.toggle_sidebar, function()
    M.toggle_sidebar()
  end, { buffer = buf, desc = 'Toggle staged sidebar' })

  -- Export
  vim.keymap.set('n', prefix .. km.export_clipboard, function()
    require('staged.export').to_clipboard()
  end, { buffer = buf, desc = 'Export to clipboard' })

  vim.keymap.set('n', prefix .. km.export_buffer, function()
    require('staged.export').to_buffer()
  end, { buffer = buf, desc = 'Export to buffer' })

  vim.keymap.set('n', prefix .. km.export_file, function()
    require('staged.export').to_file()
  end, { buffer = buf, desc = 'Export to file' })

  -- Next/prev comment
  vim.keymap.set('n', km.next_comment, function()
    M.goto_next_comment()
  end, { buffer = buf, desc = 'Next staged comment' })

  vim.keymap.set('n', km.prev_comment, function()
    M.goto_prev_comment()
  end, { buffer = buf, desc = 'Previous staged comment' })
end

---Try to bind keymaps for the current buffer if in codediff
---@return boolean success
function M.try_bind_keymaps()
  local codediff = require('staged.integration.codediff')
  if not codediff.is_in_codediff() then
    return false
  end

  local state = require('staged.core.state')
  local session = state.get_current_session()
  if not session then
    return false
  end

  local buf = vim.api.nvim_get_current_buf()
  local buf_path = vim.api.nvim_buf_get_name(buf)

  -- Match by file path, not buffer number (codediff may report stale bufnr)
  if session.current_file and buf_path == session.current_file then
    -- Update stored bufnr if it changed
    local file_state = state.get_current_file_state(session)
    if file_state and file_state.bufnr ~= buf then
      file_state.bufnr = buf
    end
    bind_keymaps_to_buffer(buf)
    return true
  end

  -- Fallback: check by stored bufnr
  local file_state = state.get_current_file_state(session)
  if file_state and buf == file_state.bufnr then
    bind_keymaps_to_buffer(buf)
    return true
  end

  return false
end

---Setup keymaps for codediff buffers
function M.setup_keymaps()
  local group = vim.api.nvim_create_augroup('staged-keymaps', { clear = true })

  vim.api.nvim_create_autocmd('BufEnter', {
    group = group,
    callback = function()
      M.try_bind_keymaps()
    end,
  })
end

---Add comment at current line
function M.add_comment_interactive()
  local state = require('staged.core.state')
  local session = state.get_current_session()
  if not session then
    vim.notify('No active staged session', vim.log.levels.WARN)
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]

  require('staged.ui.input').open({ title = 'Add Comment' }, function(text)
    if text then
      require('staged.core.comments').add(line, line, text)
      require('staged.ui.inline').render(session)
      require('staged.ui.sidebar').maybe_auto_show(session)
      require('staged.ui.sidebar').render(session)
    end
  end)
end

---Add comment for visual selection
function M.add_comment_visual()
  local state = require('staged.core.state')
  local session = state.get_current_session()
  if not session then
    return
  end

  -- Exit visual mode to get marks
  local esc = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)
  vim.api.nvim_feedkeys(esc, 'x', false)

  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")

  require('staged.ui.input').open({ title = 'Add Comment' }, function(text)
    if text then
      require('staged.core.comments').add(start_line, end_line, text)
      require('staged.ui.inline').render(session)
      require('staged.ui.sidebar').maybe_auto_show(session)
      require('staged.ui.sidebar').render(session)
    end
  end)
end

---Edit comment at cursor
function M.edit_comment_at_cursor()
  local state = require('staged.core.state')
  local session = state.get_current_session()
  if not session then
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local comment = require('staged.core.comments').get_at_line(line)

  if not comment then
    vim.notify('No comment at cursor', vim.log.levels.INFO)
    return
  end

  require('staged.ui.input').open(
    { title = 'Edit Comment', initial_text = comment.text },
    function(text)
      if text then
        require('staged.core.comments').edit(comment.id, text)
        require('staged.ui.sidebar').render(session)
      end
    end
  )
end

---Delete comment at cursor
function M.delete_comment_at_cursor()
  local state = require('staged.core.state')
  local session = state.get_current_session()
  if not session then
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local comment = require('staged.core.comments').get_at_line(line)

  if not comment then
    vim.notify('No comment at cursor', vim.log.levels.INFO)
    return
  end

  require('staged.core.comments').delete(comment.id)
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

  require('staged.core.comments').clear_all()
  require('staged.ui.inline').render(session)
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
  codediff.init_for_codediff(tabpage)
end

---Jump to next comment
function M.goto_next_comment()
  local state = require('staged.core.state')
  local session = state.get_current_session()
  if not session then
    return
  end

  local file_state = state.get_current_file_state(session)
  if not file_state then
    return
  end

  local comments = require('staged.core.comments')
  local position = require('staged.core.position')

  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local sorted = comments.get_sorted()

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
  local state = require('staged.core.state')
  local session = state.get_current_session()
  if not session then
    return
  end

  local file_state = state.get_current_file_state(session)
  if not file_state then
    return
  end

  local comments = require('staged.core.comments')
  local position = require('staged.core.position')

  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local sorted = comments.get_sorted()

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
