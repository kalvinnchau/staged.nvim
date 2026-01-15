local M = {}

---Copy content to system clipboard
---@param content string
function M.to_clipboard(content)
  vim.fn.setreg('+', content)
  vim.fn.setreg('*', content)
  vim.notify('Comments copied to clipboard', vim.log.levels.INFO)
end

---Open content in new buffer
---@param content string
function M.to_buffer(content)
  vim.cmd('tabnew')
  local buf = vim.api.nvim_get_current_buf()

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'markdown'

  local lines = vim.split(content, '\n')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.api.nvim_buf_set_name(buf, 'Staged Comments Export')
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

  file:write(content)
  file:close()

  vim.notify('Comments exported to ' .. path, vim.log.levels.INFO)
end

return M
