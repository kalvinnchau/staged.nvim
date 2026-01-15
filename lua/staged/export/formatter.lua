local M = {}

local state = require('staged.core.state')
local config = require('staged.config')
local position = require('staged.core.position')

---Get code lines from buffer
---@param bufnr integer
---@param start_line integer
---@param end_line integer
---@return string[]
local function get_code_lines(bufnr, start_line, end_line)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end
  return vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
end

---Format comments for export
---@param session StagedSession
---@param opts? { include_code?: boolean }
---@return string
function M.format(session, opts)
  opts = opts or {}
  local include_code = opts.include_code
  if include_code == nil then
    include_code = config.options.export.include_code
  end

  local comments_module = require('staged.core.comments')
  local grouped = comments_module.get_all_grouped()
  local output = {}

  -- Sort file paths for consistent ordering
  local file_paths = {}
  for file_path in pairs(grouped) do
    table.insert(file_paths, file_path)
  end
  table.sort(file_paths)

  for _, file_path in ipairs(file_paths) do
    local file_comments = grouped[file_path]
    local file_state = state.get_file_state(session, file_path)

    -- File header
    local relative_path = vim.fn.fnamemodify(file_path, ':~:.')
    table.insert(output, '## ' .. relative_path)
    table.insert(output, '')

    for _, comment in ipairs(file_comments) do
      local start_line, end_line = comment.start_line, comment.end_line
      if file_state then
        start_line, end_line = position.get_current_lines(session, file_state, comment)
      end

      -- Line reference
      if start_line == end_line then
        table.insert(output, '- **Line ' .. start_line .. '**: ' .. comment.text)
      else
        table.insert(
          output,
          '- **Lines ' .. start_line .. '-' .. end_line .. '**: ' .. comment.text
        )
      end

      -- Code snippet
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
          local ext = vim.fn.fnamemodify(file_path, ':e')
          table.insert(output, '```' .. ext)
          for _, line in ipairs(code) do
            table.insert(output, line)
          end
          table.insert(output, '```')
        end
      end

      table.insert(output, '')
    end
  end

  return table.concat(output, '\n')
end

return M
