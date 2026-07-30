local M = {}

local config = require('staged.config')

---@param text? string
---@return string|nil
local function normalize(text)
  if text == nil then
    return nil
  end

  text = vim.trim(text)
  return text ~= '' and text or nil
end

---Open input using vim.ui.input
---@param opts { title?: string, initial_text?: string }
---@param callback fun(text: string|nil)
function M.open_inline(opts, callback)
  vim.ui.input({
    prompt = (opts.title or 'Comment') .. ': ',
    default = opts.initial_text,
  }, function(text)
    callback(normalize(text))
  end)
end

---Open floating input window
---@param opts { title?: string, initial_text?: string }
---@param callback fun(text: string|nil) Called with text or nil if cancelled
function M.open_floating(opts, callback)
  local width = 60
  local height = 5

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'staged-input'

  if opts.initial_text then
    local lines = vim.split(opts.initial_text, '\n')
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end

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

  local win = vim.api.nvim_open_win(buf, true, win_opts)
  vim.wo[win].wrap = true
  vim.wo[win].cursorline = false
  vim.wo[win].winhighlight = 'FloatBorder:StagedInputBorder'

  vim.cmd('startinsert')

  local called = false

  local function close(save)
    return function()
      if called then
        return
      end
      called = true

      local text
      if save then
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        text = normalize(table.concat(lines, '\n'))
      end

      if vim.api.nvim_get_current_win() == win then
        vim.cmd('stopinsert')
      end

      if vim.api.nvim_win_is_valid(win) then
        local ok, err = pcall(vim.api.nvim_win_close, win, true)
        if not ok then
          vim.notify('Failed to close comment input: ' .. err, vim.log.levels.ERROR)
        end
      end

      callback(text)
    end
  end

  vim.keymap.set({ 'n', 'i' }, '<C-s>', close(true), { buffer = buf })
  vim.keymap.set('n', '<CR>', close(true), { buffer = buf })
  vim.keymap.set({ 'n', 'i' }, '<Esc>', close(false), { buffer = buf })
  vim.keymap.set('n', 'q', close(false), { buffer = buf })

  vim.api.nvim_create_autocmd('BufLeave', {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(close(false))
    end,
  })
end

---Open input based on config style
---@param opts { title?: string, initial_text?: string }
---@param callback fun(text: string|nil)
function M.open(opts, callback)
  if config.options.input.style == 'inline' then
    M.open_inline(opts, callback)
    return
  end

  M.open_floating(opts, callback)
end

return M
