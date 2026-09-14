-- Compatibility health report for staged.nvim.
--
-- Targets the supported integration contract: Neovim >= 0.12.5 and
-- codediff.nvim >=4.0.5 <5.0.0, driven through codediff's safe lifecycle
-- accessors. Missing required accessors are reported as unsupported.

local M = {}

local MIN_NEOVIM = '0.12.5'
local CODEDIFF_MIN = '4.0.5'
local CODEDIFF_MAX = '5.0.0'
local CODEDIFF_RANGE = '>=4.0.5, <5.0.0'
local required_accessors = {
  'get_session',
  'get_buffers',
  'get_paths',
  'get_panel_view',
  'get_git_context',
  'get_windows',
}

---@param value any
---@return string
local function error_text(value)
  return (tostring(value):match('^[^\n]+') or tostring(value))
end

---@param left string
---@param right string
---@return integer|nil nil when either side is not a parseable version
local function version_cmp(left, right)
  local ok, result = pcall(require('vim.version').cmp, left, right)
  return ok and result or nil
end

---@return string|nil version
---@return string|nil error
local function codediff_version()
  local ok, loaded = pcall(require, 'codediff.version')
  if not ok then
    return nil, error_text(loaded)
  end
  if type(loaded) ~= 'table' or type(loaded.VERSION) ~= 'string' or loaded.VERSION == '' then
    return nil, 'codediff.version did not expose VERSION'
  end
  return loaded.VERSION, nil
end

local function check_neovim()
  vim.health.start('staged.nvim')

  local ok, version = pcall(vim.version)
  local text = ok
      and type(version) == 'table'
      and type(version.major) == 'number'
      and type(version.minor) == 'number'
      and type(version.patch) == 'number'
      and string.format('%d.%d.%d', version.major, version.minor, version.patch)
    or nil

  if not text then
    vim.health.error(
      'Could not determine the Neovim version; ' .. MIN_NEOVIM .. ' or newer is required'
    )
    return
  end

  if version_cmp(text, MIN_NEOVIM) >= 0 then
    vim.health.ok('Neovim ' .. text .. ' is supported')
  else
    vim.health.error(
      'Neovim ' .. text .. ' is too old; staged.nvim requires ' .. MIN_NEOVIM .. ' or newer'
    )
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

local function report_codediff_version()
  local version, problem = codediff_version()
  if not version then
    vim.health.warn(
      'Could not determine the codediff.nvim version ('
        .. problem
        .. '); the installed version may not match the supported range '
        .. CODEDIFF_RANGE
    )
    return
  end

  local cmp_min = version_cmp(version, CODEDIFF_MIN)
  if cmp_min == nil then
    vim.health.warn(
      'codediff.nvim reports an unrecognized version "'
        .. version
        .. '"; expected a version like '
        .. CODEDIFF_MIN
        .. ' (supported: '
        .. CODEDIFF_RANGE
        .. ')'
    )
  elseif cmp_min < 0 then
    vim.health.error(
      'codediff.nvim '
        .. version
        .. ' is too old; staged.nvim requires codediff.nvim '
        .. CODEDIFF_RANGE
    )
  elseif version_cmp(version, CODEDIFF_MAX) >= 0 then
    vim.health.error(
      'codediff.nvim '
        .. version
        .. ' is too new; staged.nvim requires codediff.nvim '
        .. CODEDIFF_RANGE
    )
  else
    vim.health.ok(
      'codediff.nvim ' .. version .. ' is supported (requires ' .. CODEDIFF_RANGE .. ')'
    )
  end
end

---@param lifecycle table
---@param tabpage integer
local function report_session(lifecycle, tabpage)
  local ok, session = pcall(lifecycle.get_session, tabpage)
  if not ok then
    vim.health.error('Failed to inspect the current codediff session: ' .. error_text(session))
    return
  end
  if type(session) ~= 'table' then
    vim.health.info(
      'No active codediff session in the current tab; open a codediff diff to inspect integration'
    )
    return
  end

  vim.health.ok('Active codediff session found for tabpage ' .. tabpage)

  local details = {}
  local panel_ok, panel_name = pcall(lifecycle.get_panel_name, tabpage)
  if panel_ok and type(panel_name) == 'string' and panel_name ~= '' then
    details[#details + 1] = 'panel=' .. panel_name
  elseif
    type(session.panel) == 'table'
    and type(session.panel.name) == 'string'
    and session.panel.name ~= ''
  then
    details[#details + 1] = 'panel=' .. session.panel.name
  else
    details[#details + 1] = 'panel=none (bare diff)'
  end

  local layout_ok, layout = pcall(lifecycle.get_layout, tabpage)
  if layout_ok and type(layout) == 'string' and layout ~= '' then
    details[#details + 1] = 'layout=' .. layout
  end

  local git_ok, git = pcall(lifecycle.get_git_context, tabpage)
  if git_ok and type(git) == 'table' then
    if type(git.git_root) == 'string' and git.git_root ~= '' then
      details[#details + 1] = 'root=' .. git.git_root
    end
    if git.original_revision ~= nil or git.modified_revision ~= nil then
      local revision = function(value)
        return type(value) == 'string' and value ~= '' and value or 'WORKING'
      end
      details[#details + 1] = 'revisions='
        .. revision(git.original_revision)
        .. '..'
        .. revision(git.modified_revision)
    end
  end
  vim.health.info('Session: ' .. table.concat(details, ', '))

  local view_ok, view = pcall(lifecycle.get_panel_view, tabpage)
  if not view_ok then
    vim.health.error('Failed to inspect the codediff panel view: ' .. error_text(view))
  elseif type(view) == 'table' then
    local bits = {}
    if type(view.git_root) == 'string' and view.git_root ~= '' then
      bits[#bits + 1] = 'root=' .. view.git_root
    end
    if type(view.winid) == 'number' and vim.api.nvim_win_is_valid(view.winid) then
      bits[#bits + 1] = 'win=' .. view.winid
    end
    vim.health.info('Panel view: ' .. (#bits > 0 and table.concat(bits, ', ') or 'present'))
  else
    vim.health.info('Panel view: none (bare diff or no side panel)')
  end

  local original_buf, modified_buf, original_path, modified_path

  if type(lifecycle.get_buffers) == 'function' then
    local buffers_ok, original, modified = pcall(lifecycle.get_buffers, tabpage)
    if not buffers_ok then
      vim.health.error('Failed to inspect codediff buffers: ' .. error_text(original))
    else
      local text = function(bufnr)
        if type(bufnr) ~= 'number' then
          return nil
        end
        local state = vim.api.nvim_buf_is_valid(bufnr)
            and (vim.api.nvim_buf_is_loaded(bufnr) and 'loaded' or 'unloaded')
          or 'invalid'
        return string.format('%d (%s)', bufnr, state)
      end
      original_buf, modified_buf = text(original), text(modified)
      local usable = function(bufnr)
        return type(bufnr) == 'number' and vim.api.nvim_buf_is_valid(bufnr)
      end
      if original_buf and modified_buf and not (usable(original) and usable(modified)) then
        vim.health.warn(
          'A codediff side has no usable original and modified buffers; comments cannot attach'
        )
      end
    end
  end

  if type(lifecycle.get_paths) == 'function' then
    local paths_ok, original_ref, modified_ref = pcall(lifecycle.get_paths, tabpage)
    if not paths_ok then
      vim.health.error('Failed to inspect codediff paths: ' .. error_text(original_ref))
    else
      local text = function(ref)
        if type(ref) == 'table' then
          for _, value in ipairs({ ref.absolute, ref.relative }) do
            if type(value) == 'string' and value ~= '' then
              return value
            end
          end
          return nil
        end
        return type(ref) == 'string' and ref ~= '' and ref or nil
      end
      original_path, modified_path = text(original_ref), text(modified_ref)
    end
  end

  if original_buf and modified_buf then
    vim.health.info('Buffers: original=' .. original_buf .. ', modified=' .. modified_buf)
  end
  if original_path and modified_path then
    vim.health.info('Paths: original=' .. original_path .. ', modified=' .. modified_path)
  end

  local missing = {}
  if not (original_buf or original_path) then
    missing[#missing + 1] = 'original buffer/path unavailable'
  end
  if not (modified_buf or modified_path) then
    missing[#missing + 1] = 'modified buffer/path unavailable'
  end
  if #missing > 0 then
    vim.health.error(table.concat(missing, '; '))
  end

  if type(lifecycle.get_windows) == 'function' then
    local windows_ok, original_win, modified_win = pcall(lifecycle.get_windows, tabpage)
    if windows_ok and (type(original_win) == 'number' or type(modified_win) == 'number') then
      local text = function(win)
        return type(win) == 'number' and vim.api.nvim_win_is_valid(win) and tostring(win)
          or 'closed'
      end
      vim.health.info(
        'Windows: original=' .. text(original_win) .. ', modified=' .. text(modified_win)
      )
    end
  end
end

local function check_codediff()
  vim.health.start('codediff.nvim')

  local lifecycle_ok, lifecycle = pcall(require, 'codediff.ui.lifecycle')
  if not lifecycle_ok or type(lifecycle) ~= 'table' then
    vim.health.error('codediff.nvim is not installed or failed to load: ' .. error_text(lifecycle))
    return
  end

  report_codediff_version()

  for _, name in ipairs(required_accessors) do
    if type(lifecycle[name]) == 'function' then
      vim.health.ok('lifecycle.' .. name .. '() is available')
    else
      vim.health.error(
        'lifecycle.'
          .. name
          .. '() is missing; staged.nvim requires the codediff 4.x safe accessors'
      )
    end
  end

  report_session(lifecycle, vim.api.nvim_get_current_tabpage())
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
