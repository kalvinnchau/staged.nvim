local M = {}

local export_buffer_name = 'Staged Comments Export'

---@return string
local function next_buffer_name()
  local names = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    names[vim.api.nvim_buf_get_name(buf)] = true
  end

  local index = 1
  while true do
    local name = export_buffer_name .. (index == 1 and '' or ' ' .. index)
    if not names[vim.fn.fnamemodify(name, ':p')] then
      return name
    end
    index = index + 1
  end
end

---Copy content to system clipboard
---@param content string
function M.to_clipboard(content)
  vim.fn.setreg('+', content)
  vim.fn.setreg('*', content)
  vim.notify('Comments copied to clipboard', vim.log.levels.INFO)
end

---Open content in new buffer
---@param content string
---@param format? 'markdown'|'plain'
function M.to_buffer(content, format)
  vim.cmd('tabnew')
  local buf = vim.api.nvim_get_current_buf()

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = format == 'plain' and 'text' or 'markdown'

  local lines = vim.split(content, '\n')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.api.nvim_buf_set_name(buf, next_buffer_name())
end

---Write content to file
---@param content string
---@param path? string If nil, prompts user
function M.to_file(content, path)
  if not path then
    vim.ui.input({ prompt = 'Export to file: ', completion = 'file' }, function(input)
      if input and input ~= '' then
        M.to_file(content, input)
      end
    end)
    return
  end

  -- Expand path
  path = vim.fn.expand(path)

  local file, err = io.open(path, 'w')
  if not file then
    vim.notify('Failed to write: ' .. (err or 'unknown error'), vim.log.levels.ERROR)
    return
  end

  local write_ok, written, write_err = pcall(file.write, file, content)
  if not write_ok or not written then
    pcall(file.close, file)
    local err_message = write_ok and write_err or written
    vim.notify(
      'Failed to write: ' .. tostring(err_message or 'unknown error'),
      vim.log.levels.ERROR
    )
    return
  end

  local close_ok, closed, close_err = pcall(file.close, file)
  if not close_ok or not closed then
    local err_message = close_ok and close_err or closed
    vim.notify(
      'Failed to write: ' .. tostring(err_message or 'unknown error'),
      vim.log.levels.ERROR
    )
    return
  end

  vim.notify('Comments exported to ' .. path, vim.log.levels.INFO)
end

return M
