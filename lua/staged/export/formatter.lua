local M = {}

local state = require('staged.core.state')
local config = require('staged.config')
local position = require('staged.core.position')
local comments = require('staged.core.comments')

local export_formats = {
  json = true,
  markdown = true,
  plain = true,
}

---Get code lines from buffer, falling back to a snippet captured before the
---buffer was wiped (revision buffers are often hidden virtual buffers)
---@param file_state StagedFileState|nil
---@param comment StagedComment
---@param start_line integer
---@param end_line integer
---@return string[]
local function get_code_lines(file_state, comment, start_line, end_line)
  if
    file_state
    and vim.api.nvim_buf_is_valid(file_state.bufnr)
    and vim.api.nvim_buf_is_loaded(file_state.bufnr)
  then
    return vim.api.nvim_buf_get_lines(file_state.bufnr, start_line - 1, end_line, false)
  end
  if comment.code then
    return vim.split(comment.code, '\n')
  end
  return {}
end

---@param file_path string
---@param root string
---@return string|nil
local function get_relative_path(file_path, root)
  if file_path == '' then
    return nil
  end

  root = vim.fs.normalize(vim.fn.fnamemodify(root, ':p')):gsub('\\', '/')
  local absolute_path = vim.fs.normalize(vim.fn.fnamemodify(file_path, ':p')):gsub('\\', '/')
  local compare_root = root
  local compare_path = absolute_path

  if vim.fn.has('win32') == 1 then
    compare_root = compare_root:lower()
    compare_path = compare_path:lower()
  end

  local prefix = compare_root:sub(-1) == '/' and compare_root or compare_root .. '/'
  if compare_path:sub(1, #prefix) ~= prefix then
    return nil
  end

  return absolute_path:sub(#prefix + 1)
end

---@param session StagedSession
---@param grouped table<string, StagedComment[]>
---@param file_keys string[]
---@param include_code boolean
---@return string
local function format_json(session, grouped, file_keys, include_code)
  local records = {}

  for _, file_key in ipairs(file_keys) do
    local file_state = state.get_file_state(session, file_key)
    local file_path = file_state and file_state.file_path or nil
    local relative_path = file_path and get_relative_path(file_path, session.root) or nil

    for _, comment in ipairs(grouped[file_key]) do
      local start_line, end_line = comment.start_line, comment.end_line
      if file_state then
        start_line, end_line = position.get_current_lines(session, file_state, comment)
      end

      local record = {
        path = relative_path,
        start_line = start_line,
        end_line = end_line,
        modified_revision = state.normalize_revision(comment.modified_revision),
        original_revision = comment.original_revision ~= nil and state.normalize_revision(
          comment.original_revision
        ) or nil,
        side = 'modified',
        text = comment.text,
      }

      if include_code then
        local code = get_code_lines(file_state, comment, start_line, end_line)
        local snippet = table.concat(code, '\n')
        if snippet:match('%S') then
          record.code = snippet
        end
      end

      table.insert(records, record)
    end
  end

  return vim.json.encode({ schema_version = 2, comments = records }, { sort_keys = true })
end

---Format comments for export
---@param session StagedSession
---@param opts? { include_code?: boolean, format?: 'markdown'|'plain'|'json' }
---@return string
function M.format(session, opts)
  if opts ~= nil and type(opts) ~= 'table' then
    error('staged.nvim: export options must be a table', 2)
  end
  opts = opts or {}
  if opts.format ~= nil and not export_formats[opts.format] then
    error('staged.nvim: export.format must be one of: markdown, plain, json', 2)
  end
  if opts.include_code ~= nil and type(opts.include_code) ~= 'boolean' then
    error('staged.nvim: export.include_code must be a boolean', 2)
  end

  local include_code = opts.include_code
  if include_code == nil then
    include_code = config.options.export.include_code
  end

  local format = opts.format or config.options.export.format
  local grouped = comments.get_all_grouped(session)
  local output = {}

  local file_keys = {}
  for file_key in pairs(grouped) do
    table.insert(file_keys, file_key)
  end
  table.sort(file_keys)

  if format == 'json' then
    return format_json(session, grouped, file_keys, include_code)
  end

  for _, file_key in ipairs(file_keys) do
    local file_comments = grouped[file_key]
    local file_state = state.get_file_state(session, file_key)
    local file_path = file_state and file_state.file_path or file_key

    local relative_path = get_relative_path(file_path, session.root)
      or vim.fn.fnamemodify(file_path, ':~')
    if file_state and file_state.modified_revision ~= 'WORKING' then
      relative_path = relative_path .. ' [modified: ' .. file_state.modified_revision .. ']'
    end
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

      if include_code then
        local code = get_code_lines(file_state, comment, start_line, end_line)
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
