local M = {}

local state = require('staged.core.state')
local config = require('staged.config')
local position = require('staged.core.position')

---@param bufnr integer
---@return integer|nil
local function get_line_count(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  if not vim.api.nvim_buf_is_loaded(bufnr) then
    return nil
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count < 1 then
    return nil
  end

  return line_count
end

---@param file_state StagedFileState
---@param start_line integer
---@param end_line integer
---@return integer|nil, integer|nil
local function get_render_range(file_state, start_line, end_line)
  local line_count = get_line_count(file_state.bufnr)
  if not line_count then
    return nil, nil
  end

  local clamped_start = math.max(1, math.min(start_line, line_count))
  local clamped_end = math.max(clamped_start, math.min(end_line, line_count))
  return clamped_start, clamped_end
end

---@param session StagedSession
---@param file_path? string
---@return StagedFileState|nil
local function get_file_state(session, file_path)
  if file_path then
    return state.get_file_state(session, file_path)
  end
  return state.get_current_file_state(session)
end

---Render indicators for a file's comments
---@param session StagedSession
---@param file_path? string Defaults to the current file
function M.render(session, file_path)
  M.clear(session, file_path)

  local file_state = get_file_state(session, file_path)
  if not file_state or not get_line_count(file_state.bufnr) then
    return
  end

  local style = config.options.inline.style
  local start_counts = {}
  local highlighted_lines = {}

  for _, comment in pairs(file_state.comments) do
    local start_line, end_line = position.get_current_lines(session, file_state, comment)
    start_line, end_line = get_render_range(file_state, start_line, end_line)

    if start_line then
      if style == 'line_highlight' then
        for line = start_line, end_line do
          highlighted_lines[line] = true
        end
      else
        start_counts[start_line] = (start_counts[start_line] or 0) + 1
      end
    end
  end

  if style == 'line_highlight' then
    for line in pairs(highlighted_lines) do
      M.render_line_highlight(session, file_state, line)
    end
    return
  end

  for line, count in pairs(start_counts) do
    if style == 'sign' then
      M.render_sign(session, file_state, line)
    else
      M.render_virtual_text(session, file_state, line, count)
    end
  end
end

---Clear indicators for a file
---@param session StagedSession
---@param file_path? string Defaults to the current file
function M.clear(session, file_path)
  local file_state = get_file_state(session, file_path)
  if not file_state or not vim.api.nvim_buf_is_valid(file_state.bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(file_state.bufnr, session.indicator_ns_id, 0, -1)
end

---Clear indicators from every file in a session
---@param session StagedSession
function M.clear_all(session)
  for file_path in pairs(session.files) do
    M.clear(session, file_path)
  end
end

---@param session StagedSession
---@param file_state StagedFileState
---@param line integer
function M.render_sign(session, file_state, line)
  vim.api.nvim_buf_set_extmark(file_state.bufnr, session.indicator_ns_id, line - 1, 0, {
    sign_text = config.options.inline.sign_icon,
    sign_hl_group = 'StagedCommentSign',
  })
end

---@param session StagedSession
---@param file_state StagedFileState
---@param line integer
---@param count integer
function M.render_virtual_text(session, file_state, line, count)
  local format = config.options.inline.virtual_text_format
  local text = string.format(format, count)

  vim.api.nvim_buf_set_extmark(file_state.bufnr, session.indicator_ns_id, line - 1, 0, {
    virt_text = { { text, 'StagedCommentVirtText' } },
    virt_text_pos = 'eol',
  })
end

---@param session StagedSession
---@param file_state StagedFileState
---@param line integer
function M.render_line_highlight(session, file_state, line)
  vim.api.nvim_buf_set_extmark(file_state.bufnr, session.indicator_ns_id, line - 1, 0, {
    line_hl_group = 'StagedCommentLine',
  })
end

return M
