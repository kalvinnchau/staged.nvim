local M = {}

local state = require('staged.core.state')
local config = require('staged.config')
local formatter = require('staged.export.formatter')
local destinations = require('staged.export.destinations')

---Export comments to clipboard
---@param opts? { include_code?: boolean, format?: 'markdown'|'plain'|'json' }
function M.to_clipboard(opts)
  local session = state.get_current_session()
  if not session then
    vim.notify('No active staged session', vim.log.levels.WARN)
    return
  end

  local content = formatter.format(session, opts)
  destinations.to_clipboard(content)
end

---Export comments to new buffer
---@param opts? { include_code?: boolean, format?: 'markdown'|'plain'|'json' }
function M.to_buffer(opts)
  local session = state.get_current_session()
  if not session then
    vim.notify('No active staged session', vim.log.levels.WARN)
    return
  end

  local content = formatter.format(session, opts)
  local format = opts and opts.format or config.options.export.format
  destinations.to_buffer(content, format)
end

---Export comments to file
---@param path? string
---@param opts? { include_code?: boolean, format?: 'markdown'|'plain'|'json' }
function M.to_file(path, opts)
  local session = state.get_current_session()
  if not session then
    vim.notify('No active staged session', vim.log.levels.WARN)
    return
  end

  local content = formatter.format(session, opts)
  destinations.to_file(content, path)
end

return M
