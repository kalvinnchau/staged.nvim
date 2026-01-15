local M = {}

---Create a test buffer with content
---@param lines string[]
---@return integer bufnr
function M.create_test_buffer(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

---Create a mock session for testing without codediff
---@param buf integer
---@param path string
---@return StagedSession
function M.create_mock_session(buf, path)
  local state = require('staged.core.state')
  local tabpage = vim.api.nvim_get_current_tabpage()
  local session = state.create_session(tabpage)
  state.set_current_file(session, path, buf)
  return session
end

---Clean up test session
function M.cleanup_session()
  local state = require('staged.core.state')
  local tabpage = vim.api.nvim_get_current_tabpage()
  state.destroy_session(tabpage)
end

---Set cursor position in a window
---@param win integer
---@param line integer
---@param col integer
function M.set_cursor(win, line, col)
  vim.api.nvim_win_set_cursor(win, { line, col or 0 })
end

---Get buffer lines
---@param buf integer
---@return string[]
function M.get_buffer_lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

---Count extmarks in a buffer namespace
---@param buf integer
---@param ns integer
---@return integer
function M.count_extmarks(buf, ns)
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
  return #marks
end

---Get sign extmarks for a buffer (0.10+ uses extmarks for signs)
---@param buf integer
---@param ns integer namespace id
---@return table[] list of {line, details}
function M.get_sign_extmarks(buf, ns)
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  local signs = {}
  for _, mark in ipairs(marks) do
    local details = mark[4]
    if details and details.sign_text then
      table.insert(signs, { lnum = mark[2] + 1, text = details.sign_text })
    end
  end
  return signs
end

---Get signs for a buffer (compatibility wrapper)
---@param buf integer
---@param group string|integer namespace name or id
---@return table[]
function M.get_signs(buf, group)
  local highlights = require('staged.ui.highlights')
  return M.get_sign_extmarks(buf, highlights.ns_indicators)
end

---Simulate adding a comment via the API
---@param start_line integer
---@param end_line integer
---@param text string
---@return StagedComment|nil
function M.add_comment(start_line, end_line, text)
  local comments = require('staged.core.comments')
  return comments.add(start_line, end_line, text)
end

---Get clipboard content
---@return string
function M.get_clipboard()
  return vim.fn.getreg('+')
end

---Default test file content
M.default_lines = {
  'local M = {}',
  '',
  'function M.hello()',
  '  print("hello")',
  'end',
  '',
  'function M.world()',
  '  print("world")',
  'end',
  '',
  'return M',
}

return M
