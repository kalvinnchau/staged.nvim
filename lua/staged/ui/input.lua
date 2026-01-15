local M = {}

local config = require('staged.config')

---Open floating input window
---@param opts { title: string, initial_text?: string }
---@param callback fun(text: string|nil) Called with text or nil if cancelled
function M.open_floating(opts, callback)
  local width = 60
  local height = 5

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'staged-input'

  -- Set initial text if provided
  if opts.initial_text then
    local lines = vim.split(opts.initial_text, '\n')
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end

  -- Calculate position (centered relative to cursor)
  local win_opts = {
    relative = 'cursor',
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
    title = ' ' .. (opts.title or 'Comment') .. ' ',
    title_pos = 'center',
  }

  -- Open window
  local win = vim.api.nvim_open_win(buf, true, win_opts)
  vim.wo[win].wrap = true
  vim.wo[win].cursorline = false

  -- Enter insert mode
  vim.cmd('startinsert')

  -- Track if callback was already called
  local called = false

  -- Setup keymaps for the input buffer
  local function close(save)
    return function()
      if called then
        return
      end
      called = true

      if save then
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local text = table.concat(lines, '\n')
        text = vim.trim(text)
        if text ~= '' then
          callback(text)
        else
          callback(nil)
        end
      else
        callback(nil)
      end

      -- Close window if still valid
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end

      -- Return to normal mode
      vim.cmd('stopinsert')
    end
  end

  -- Ctrl+S to save
  vim.keymap.set({ 'n', 'i' }, '<C-s>', close(true), { buffer = buf })
  -- Enter in normal mode to save
  vim.keymap.set('n', '<CR>', close(true), { buffer = buf })

  -- Escape or q to cancel
  vim.keymap.set('n', '<Esc>', close(false), { buffer = buf })
  vim.keymap.set('n', 'q', close(false), { buffer = buf })

  -- Close on buffer leave
  vim.api.nvim_create_autocmd('BufLeave', {
    buffer = buf,
    once = true,
    callback = close(false),
  })
end

---Open input based on config style
---@param opts { title: string, initial_text?: string }
---@param callback fun(text: string|nil)
function M.open(opts, callback)
  local style = config.options.input.style

  if style == 'floating' then
    M.open_floating(opts, callback)
  else
    -- For now, always use floating. Inline can be added later.
    M.open_floating(opts, callback)
  end
end

return M
