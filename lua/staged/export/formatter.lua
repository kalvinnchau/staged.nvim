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

---@param name string
---@param value any
---@return string
local function encode_field(name, value)
  -- Object key order from vim.json.encode is unspecified, so encode fields individually.
  return vim.json.encode(name) .. ':' .. vim.json.encode(value)
end

---@param session StagedSession
---@param grouped table<string, StagedComment[]>
---@param file_paths string[]
---@param include_code boolean
---@return string
local function format_json(session, grouped, file_paths, include_code)
  local encoded_comments = {}

  for _, file_path in ipairs(file_paths) do
    local file_state = state.get_file_state(session, file_path)
    local relative_path = get_relative_path(file_path, session.root)

    for _, comment in ipairs(grouped[file_path]) do
      local start_line, end_line = comment.start_line, comment.end_line
      if file_state then
        start_line, end_line = position.get_current_lines(session, file_state, comment)
      end

      local fields = {}
      if relative_path then
        table.insert(fields, encode_field('path', relative_path))
      end
      table.insert(fields, encode_field('start_line', start_line))
      table.insert(fields, encode_field('end_line', end_line))
      table.insert(fields, encode_field('text', comment.text))

      if include_code and file_state then
        local code = get_code_lines(file_state.bufnr, start_line, end_line)
        local snippet = table.concat(code, '\n')
        if snippet:match('%S') then
          table.insert(fields, encode_field('code', snippet))
        end
      end

      table.insert(encoded_comments, '{' .. table.concat(fields, ',') .. '}')
    end
  end

  return table.concat({
    '{',
    encode_field('schema_version', 1),
    ',',
    vim.json.encode('comments'),
    ':[',
    table.concat(encoded_comments, ','),
    ']}',
  })
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

  local file_paths = {}
  for file_path in pairs(grouped) do
    table.insert(file_paths, file_path)
  end
  table.sort(file_paths)

  if format == 'json' then
    return format_json(session, grouped, file_paths, include_code)
  end

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
