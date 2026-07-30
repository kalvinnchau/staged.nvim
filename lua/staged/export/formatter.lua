local M = {}

local state = require('staged.core.state')
local config = require('staged.config')
local position = require('staged.core.position')
local comments = require('staged.core.comments')

---Get code lines from buffer
---@param bufnr integer
---@param start_line integer
---@param end_line integer
---@return string[]
local function get_code_lines(bufnr, start_line, end_line)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return {}
  end
  return vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
end

---Format comments for export
---@param session StagedSession
---@param opts? { include_code?: boolean, format?: 'markdown'|'plain' }
---@return string
function M.format(session, opts)
  opts = opts or {}
  local include_code = opts.include_code
  if include_code == nil then
    include_code = config.options.export.include_code
  end

  local format = opts.format or config.options.export.format
  local grouped = comments.get_all_grouped(session)
  local output = {}

  local file_paths = {}
  for file_path in pairs(grouped) do
    table.insert(file_paths, file_path)
  end
  table.sort(file_paths)

  for _, file_path in ipairs(file_paths) do
    local file_comments = grouped[file_path]
    local file_state = state.get_file_state(session, file_path)

    local relative_path = vim.fn.fnamemodify(file_path, ':~:.')
    table.insert(output, format == 'plain' and relative_path or '## ' .. relative_path)
    table.insert(output, '')

    for _, comment in ipairs(file_comments) do
      local start_line, end_line = comment.start_line, comment.end_line
      if file_state then
        start_line, end_line = position.get_current_lines(session, file_state, comment)
      end

      local line_reference
      if start_line == end_line then
        line_reference = 'Line ' .. start_line
      else
        line_reference = 'Lines ' .. start_line .. '-' .. end_line
      end

      if format == 'plain' then
        table.insert(output, line_reference .. ': ' .. comment.text)
      else
        table.insert(output, '- **' .. line_reference .. '**: ' .. comment.text)
      end

      if include_code and file_state then
        local code = get_code_lines(file_state.bufnr, start_line, end_line)
        local has_content = false
        for _, line in ipairs(code) do
          if line:match('%S') then
            has_content = true
            break
          end
        end
        if #code > 0 and has_content then
          if format == 'plain' then
            for _, line in ipairs(code) do
              table.insert(output, '    ' .. line)
            end
          else
            local ext = vim.fn.fnamemodify(file_path, ':e')
            table.insert(output, '```' .. ext)
            for _, line in ipairs(code) do
              table.insert(output, line)
            end
            table.insert(output, '```')
          end
        end
      end

      table.insert(output, '')
    end
  end

  return table.concat(output, '\n')
end

return M
