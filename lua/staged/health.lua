local M = {}

---@param value any
---@return string
local function error_text(value)
  return tostring(value):match('^[^\n]+') or tostring(value)
end

local function check_neovim()
  vim.health.start('staged.nvim')

  local version = vim.version()
  local version_text = string.format('%d.%d.%d', version.major, version.minor, version.patch)
  if version.major > 0 or version.minor >= 10 then
    vim.health.ok('Neovim ' .. version_text .. ' is supported')
  else
    vim.health.error('Neovim 0.10.0 or newer is required; found ' .. version_text)
  end
end

local function check_configuration()
  vim.health.start('configuration')

  local staged_ok, staged = pcall(require, 'staged')
  if not staged_ok then
    vim.health.error('Failed to load staged.nvim: ' .. error_text(staged))
    return
  end
  if type(staged.setup) ~= 'function' then
    vim.health.error('staged.setup() is unavailable')
  else
    vim.health.ok('staged.setup() is available')
  end

  local config_ok, config = pcall(require, 'staged.config')
  if not config_ok then
    vim.health.error('Failed to load configuration: ' .. error_text(config))
    return
  end
  if type(config.setup) ~= 'function' or type(config.options) ~= 'table' then
    vim.health.error('Configuration module is invalid')
    return
  end

  local original_options = config.options
  local validation_ok, validation_error = pcall(function()
    config.setup(vim.deepcopy(original_options))
  end)
  config.options = original_options

  if validation_ok then
    vim.health.ok('Current configuration is valid')
  else
    vim.health.error('Current configuration is invalid: ' .. error_text(validation_error))
  end
end

---@param path table|string|nil
---@return string|nil
local function resolve_path(path)
  if type(path) == 'table' then
    for _, value in ipairs({ path.absolute, path.relative }) do
      if type(value) == 'string' and value ~= '' then
        return value
      end
    end
  end
  if type(path) == 'string' and path ~= '' then
    return path
  end
  return nil
end

---@param bufnr any
---@return string
local function format_buffer(bufnr)
  if type(bufnr) ~= 'number' then
    return '[unavailable]'
  end

  local valid = vim.api.nvim_buf_is_valid(bufnr)
  local loaded = valid and vim.api.nvim_buf_is_loaded(bufnr)
  return string.format('%d (%s)', bufnr, loaded and 'loaded' or valid and 'unloaded' or 'invalid')
end

local function check_codediff()
  vim.health.start('codediff.nvim')

  local lifecycle_ok, lifecycle = pcall(require, 'codediff.ui.lifecycle')
  if not lifecycle_ok then
    vim.health.error('codediff lifecycle is unavailable: ' .. error_text(lifecycle))
    return
  end
  vim.health.ok('codediff lifecycle is available')

  if type(lifecycle.get_session) ~= 'function' then
    vim.health.error('codediff lifecycle.get_session() is unavailable')
    return
  end
  vim.health.ok('codediff lifecycle.get_session() is available')

  for _, name in ipairs({ 'get_buffers', 'get_paths' }) do
    if type(lifecycle[name]) == 'function' then
      vim.health.ok('codediff lifecycle.' .. name .. '() is available')
    else
      vim.health.info('codediff lifecycle.' .. name .. '() is unavailable; using legacy fields')
    end
  end

  local tabpage = vim.api.nvim_get_current_tabpage()
  local session_ok, session = pcall(lifecycle.get_session, tabpage)
  if not session_ok then
    vim.health.error('Failed to inspect the current codediff session: ' .. error_text(session))
    return
  end
  if not session then
    vim.health.info('No active codediff session in the current tab')
    return
  end

  vim.health.ok('Active codediff session found for tabpage ' .. tabpage)
  local details = {}
  for _, name in ipairs({ 'mode', 'layout', 'git_root' }) do
    if session[name] ~= nil then
      table.insert(details, name .. '=' .. tostring(session[name]))
    end
  end
  if #details > 0 then
    vim.health.info('Session: ' .. table.concat(details, ', '))
  end

  local original_bufnr = session.original_bufnr
  local modified_bufnr = session.modified_bufnr
  if type(lifecycle.get_buffers) == 'function' then
    local buffers_ok, original, modified = pcall(lifecycle.get_buffers, tabpage)
    if buffers_ok then
      original_bufnr = original or original_bufnr
      modified_bufnr = modified or modified_bufnr
    else
      vim.health.error('Failed to inspect codediff buffers: ' .. error_text(original))
    end
  end
  if type(original_bufnr) == 'number' and type(modified_bufnr) == 'number' then
    vim.health.info(
      'Buffers: original='
        .. format_buffer(original_bufnr)
        .. ', modified='
        .. format_buffer(modified_bufnr)
    )
  else
    vim.health.error('No usable original and modified codediff buffers were found')
  end

  local original_path = session.original or session.original_path
  local modified_path = session.modified or session.modified_path
  if type(lifecycle.get_paths) == 'function' then
    local paths_ok, original, modified = pcall(lifecycle.get_paths, tabpage)
    if paths_ok then
      original_path = original or original_path
      modified_path = modified or modified_path
    else
      vim.health.error('Failed to inspect codediff paths: ' .. error_text(original))
    end
  end
  local resolved_original = resolve_path(original_path)
  local resolved_modified = resolve_path(modified_path)
  if resolved_original and resolved_modified then
    vim.health.info('Paths: original=' .. resolved_original .. ', modified=' .. resolved_modified)
  else
    vim.health.error('No usable original and modified codediff paths were found')
  end
end

local function check_clipboard()
  vim.health.start('optional features')

  local ok, available = pcall(vim.fn.has, 'clipboard')
  if ok and available == 1 then
    vim.health.ok('Clipboard provider is available')
  else
    vim.health.info('No clipboard provider detected; clipboard export will be unavailable')
  end
end

function M.check()
  check_neovim()
  check_configuration()
  check_codediff()
  check_clipboard()
end

return M
