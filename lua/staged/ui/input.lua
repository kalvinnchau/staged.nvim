local M = {}

local config = require('staged.config')

local base_width = 60
local min_height = 5

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

local function max_dimensions()
  return math.max(1, vim.o.columns - 2), math.max(1, vim.o.lines - vim.o.cmdheight - 3)
end

---Open floating input window
---@param opts { title?: string, initial_text?: string }
---@param callback fun(text: string|nil) Called with text or nil if cancelled
function M.open_floating(opts, callback)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'staged-input'

  if opts.initial_text then
    local lines = vim.split(opts.initial_text, '\n')
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end

  local max_width, max_height = max_dimensions()
  local width, height = math.min(base_width, max_width), math.min(min_height, max_height)

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

  local function resize()
    if not vim.api.nvim_win_is_valid(win) then
      return
    end
    local max_width, max_height = max_dimensions()
    vim.api.nvim_win_set_config(win, { width = math.min(base_width, max_width) })
    local measured = vim.api.nvim_win_text_height(win, { max_height = max_height }).all
    vim.api.nvim_win_set_config(
      win,
      { height = math.min(max_height, math.max(min_height, measured)) }
    )
  end

  vim.cmd('startinsert')

  local called = false
  local augroup = vim.api.nvim_create_augroup('staged-input-' .. buf, { clear = true })

  local function cleanup()
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
  end

  local function close(save)
    return function()
      if called then
        return
      end
      called = true

      cleanup()

      local text
      if save and vim.api.nvim_buf_is_valid(buf) then
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
  vim.keymap.set('n', '<Esc>', close(false), { buffer = buf })
  vim.keymap.set('n', 'q', close(false), { buffer = buf })

  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'TextChangedP' }, {
    group = augroup,
    buffer = buf,
    callback = vim.schedule_wrap(resize),
  })

  vim.api.nvim_create_autocmd('VimResized', {
    group = augroup,
    callback = resize,
  })

  -- Wiping the buffer (e.g. via external command) must still invoke the
  -- callback exactly once and tear down autocmds
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = augroup,
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(close(false))
    end,
  })

  -- Fallback if the user leaves the window without closing
  vim.api.nvim_create_autocmd('BufLeave', {
    group = augroup,
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(close(false))
    end,
  })

  -- The window must exist before measuring its wrapped text.
  resize()
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
