local M = {}

local state = require('staged.core.state')
local config = require('staged.config')
local position = require('staged.core.position')
local highlights = require('staged.ui.highlights')

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

---Render indicators for current file's comments
---@param session StagedSession
function M.render(session)
  M.clear(session)

  local file_state = state.get_current_file_state(session)
  if not file_state or not get_line_count(file_state.bufnr) then
    return
  end

  local style = config.options.inline.style

  for _, comment in pairs(file_state.comments) do
    local start_line, end_line = position.get_current_lines(session, file_state, comment)
    start_line, end_line = get_render_range(file_state, start_line, end_line)

    if start_line then
      if style == 'sign' then
        M.render_sign(file_state, start_line)
      elseif style == 'virtual_text' then
        M.render_virtual_text(file_state, start_line, comment)
      elseif style == 'line_highlight' then
        M.render_line_highlight(file_state, start_line, end_line)
      end
    end
  end
end

---Clear all indicators for current file
---@param session StagedSession
function M.clear(session)
  local file_state = state.get_current_file_state(session)
  if not file_state or not vim.api.nvim_buf_is_valid(file_state.bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(file_state.bufnr, highlights.ns_indicators, 0, -1)
end

---@param file_state StagedFileState
---@param line integer
function M.render_sign(file_state, line)
  vim.api.nvim_buf_set_extmark(file_state.bufnr, highlights.ns_indicators, line - 1, 0, {
    sign_text = config.options.inline.sign_icon,
    sign_hl_group = 'StagedCommentSign',
  })
end

---@param file_state StagedFileState
---@param line integer
---@param _comment StagedComment
---@diagnostic disable-next-line: unused-local
function M.render_virtual_text(file_state, line, _comment)
  local format = config.options.inline.virtual_text_format
  local text = string.format(format, 1) -- Always 1 comment per line for now

  vim.api.nvim_buf_set_extmark(file_state.bufnr, highlights.ns_indicators, line - 1, 0, {
    virt_text = { { text, 'StagedCommentVirtText' } },
    virt_text_pos = 'eol',
  })
end

---@param file_state StagedFileState
---@param start_line integer
---@param end_line integer
function M.render_line_highlight(file_state, start_line, end_line)
  for line = start_line, end_line do
    vim.api.nvim_buf_set_extmark(file_state.bufnr, highlights.ns_indicators, line - 1, 0, {
      line_hl_group = 'StagedCommentLine',
    })
  end
end

return M
