local M = {}

local state = require('staged.core.state')
local formatter = require('staged.export.formatter')
local destinations = require('staged.export.destinations')

---Export comments to clipboard
function M.to_clipboard()
  local session = state.get_current_session()
  if not session then
    vim.notify('No active staged session', vim.log.levels.WARN)
    return
  end

  local content = formatter.format(session)
  destinations.to_clipboard(content)
end

---Export comments to new buffer
function M.to_buffer()
  local session = state.get_current_session()
  if not session then
    vim.notify('No active staged session', vim.log.levels.WARN)
    return
  end

  local content = formatter.format(session)
  destinations.to_buffer(content)
end

---Export comments to file
---@param path? string
function M.to_file(path)
  local session = state.get_current_session()
  if not session then
    vim.notify('No active staged session', vim.log.levels.WARN)
    return
  end

  local content = formatter.format(session)
  destinations.to_file(content, path)
end

return M
