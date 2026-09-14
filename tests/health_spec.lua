describe('health', function()
  local original_health
  local original_version_fn
  local original_version_parse
  local original_lifecycle
  local original_lifecycle_preload
  local original_version_module
  local original_version_preload
  local original_options
  local original_has
  local records
  local buffers
  local windows

  local function contains(level, text)
    for _, record in ipairs(records) do
      if record.level == level and record.message:find(text, 1, true) then
        return true
      end
    end
    return false
  end

  local function run_check()
    package.loaded['staged.health'] = nil
    require('staged.health').check()
  end

  local function create_float_window()
    local bufnr = vim.api.nvim_create_buf(false, true)
    local winid = vim.api.nvim_open_win(bufnr, false, {
      relative = 'editor',
      width = 10,
      height = 5,
      row = 0,
      col = 0,
    })
    table.insert(buffers, bufnr)
    table.insert(windows, winid)
    return winid
  end

  ---@param version string|table|nil
  ---@param err string|nil
  local function stub_codediff_version(version, err)
    package.loaded['codediff.version'] = nil
    if err then
      package.preload['codediff.version'] = function()
        error(err)
      end
    elseif version == nil then
      package.preload['codediff.version'] = function()
        return {}
      end
    else
      package.preload['codediff.version'] = function()
        return { VERSION = version }
      end
    end
    -- The codediff check returns before reporting the version without a lifecycle.
    package.loaded['codediff.ui.lifecycle'] = { get_session = function() end }
  end

  before_each(function()
    original_health = vim.health
    original_version_fn = vim.version
    original_version_parse = vim.version.parse
    original_lifecycle = package.loaded['codediff.ui.lifecycle']
    original_lifecycle_preload = package.preload['codediff.ui.lifecycle']
    original_version_module = package.loaded['codediff.version']
    original_version_preload = package.preload['codediff.version']
    original_options = require('staged.config').options
    original_has = vim.fn.has
    records = {}
    buffers = {}
    windows = {}

    vim.health = {}
    for _, level in ipairs({ 'start', 'ok', 'info', 'warn', 'error' }) do
      vim.health[level] = function(message)
        table.insert(records, { level = level, message = message })
      end
    end
  end)

  after_each(function()
    vim.health = original_health
    vim.version = original_version_fn
    vim.version.parse = original_version_parse
    package.loaded['codediff.ui.lifecycle'] = original_lifecycle
    package.preload['codediff.ui.lifecycle'] = original_lifecycle_preload
    package.loaded['codediff.version'] = original_version_module
    package.preload['codediff.version'] = original_version_preload
    package.loaded['staged.health'] = nil
    require('staged.config').options = original_options
    vim.fn.has = original_has

    for _, bufnr in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end

    for _, winid in ipairs(windows) do
      if vim.api.nvim_win_is_valid(winid) then
        vim.api.nvim_win_close(winid, true)
      end
    end
  end)

  it('reports supported runtime, configuration, and an active codediff session', function()
    local original_bufnr = vim.api.nvim_create_buf(false, true)
    local modified_bufnr = vim.api.nvim_create_buf(false, true)
    local panel_winid = create_float_window()
    table.insert(buffers, original_bufnr)
    table.insert(buffers, modified_bufnr)

    local tabpage = vim.api.nvim_get_current_tabpage()
    package.loaded['codediff.ui.lifecycle'] = {
      get_session = function(requested_tabpage)
        if requested_tabpage == tabpage then
          return {
            panel = { name = 'explorer' },
            layout = 'side-by-side',
          }
        end
      end,
      get_panel_name = function()
        return 'explorer'
      end,
      get_layout = function()
        return 'side-by-side'
      end,
      get_git_context = function()
        return {
          git_root = '/repo',
          original_revision = 'HEAD~1',
          modified_revision = 'WORKING',
        }
      end,
      get_buffers = function()
        return original_bufnr, modified_bufnr
      end,
      get_paths = function()
        return { absolute = '/repo/original.lua' }, { absolute = '/repo/modified.lua' }
      end,
      get_windows = function()
        return nil, panel_winid
      end,
      get_panel_view = function()
        return { git_root = '/repo', winid = panel_winid }
      end,
    }

    run_check()

    assert.is_true(contains('ok', 'Neovim 0.12.5 is supported'))
    assert.is_true(contains('ok', 'Current configuration is valid'))
    assert.is_true(contains('ok', 'Active codediff session found'))
    for _, name in ipairs({
      'get_session',
      'get_buffers',
      'get_paths',
      'get_panel_view',
      'get_git_context',
      'get_windows',
    }) do
      assert.is_true(contains('ok', 'lifecycle.' .. name .. '() is available'))
    end
    assert.is_true(contains('info', 'panel=explorer'))
    assert.is_true(contains('info', 'layout=side-by-side'))
    assert.is_true(contains('info', 'root=/repo'))
    assert.is_true(contains('info', 'revisions=HEAD~1..WORKING'))
    assert.is_true(contains('info', 'modified=' .. modified_bufnr))
    assert.is_true(contains('info', 'modified=/repo/modified.lua'))
    assert.is_true(contains('info', 'win=' .. panel_winid))
    assert.is_true(contains('info', 'modified=' .. panel_winid))
    assert.is_false(contains('info', 'Legacy session fields'))
  end)

  it('reports an unsupported (old) Neovim runtime', function()
    vim.version = function()
      return { major = 0, minor = 11, patch = 4 }
    end

    run_check()

    assert.is_true(contains('error', 'Neovim 0.11.4 is too old'))
  end)

  it('supports the exact minimum runtime 0.12.5', function()
    vim.version = function()
      return { major = 0, minor = 12, patch = 5 }
    end

    run_check()

    assert.is_true(contains('ok', 'Neovim 0.12.5 is supported'))
  end)

  it('reports a missing Neovim version table as an error, not a crash', function()
    vim.version = function()
      error('no version table')
    end

    assert.has_no.errors(run_check)
    assert.is_true(contains('error', 'Could not determine the Neovim version'))
  end)

  it('is robust when codediff is absent', function()
    package.loaded['codediff.ui.lifecycle'] = nil
    package.preload['codediff.ui.lifecycle'] = function()
      error('not installed')
    end

    assert.has_no.errors(run_check)
    assert.is_true(contains('error', 'codediff.nvim is not installed or failed to load'))
  end)

  it('reports missing lifecycle accessors as unsupported, without legacy fallback', function()
    package.loaded['codediff.ui.lifecycle'] = {
      get_session = function()
        return {
          original_bufnr = 111,
          modified_bufnr = 222,
          original_path = '/repo/original.lua',
          modified_path = '/repo/modified.lua',
          mode = 'explorer',
        }
      end,
    }

    run_check()

    for _, name in ipairs({
      'get_buffers',
      'get_paths',
      'get_panel_view',
      'get_git_context',
      'get_windows',
    }) do
      assert.is_true(contains('error', 'lifecycle.' .. name .. '() is missing'))
    end
    assert.is_false(contains('info', 'Legacy session fields'))
    assert.is_false(contains('info', 'mode=explorer'))
    assert.is_false(contains('info', 'Buffers: original='))
    assert.is_false(contains('info', 'Paths: original='))
    assert.is_false(contains('error', 'No usable'))
  end)

  it('does not substitute legacy fields for required accessors', function()
    local original_bufnr = vim.api.nvim_create_buf(false, true)
    local modified_bufnr = vim.api.nvim_create_buf(false, true)
    table.insert(buffers, original_bufnr)
    table.insert(buffers, modified_bufnr)
    package.loaded['codediff.ui.lifecycle'] = {
      get_session = function()
        return {
          original_bufnr = original_bufnr,
          modified_bufnr = modified_bufnr,
          original_path = '/repo/original.lua',
          modified_path = '/repo/modified.lua',
        }
      end,
    }

    run_check()

    assert.is_false(contains('info', 'Legacy session fields'))
    assert.is_false(contains('info', 'original_bufnr=' .. original_bufnr))
    assert.is_false(contains('info', 'modified_bufnr=' .. modified_bufnr))
    assert.is_false(contains('info', 'Buffers: original='))
    assert.is_false(contains('info', 'Paths: original='))
    assert.is_false(contains('error', 'No usable'))
  end)

  it('reports errors from throwing lifecycle accessors without crashing', function()
    local original_bufnr = vim.api.nvim_create_buf(false, true)
    local modified_bufnr = vim.api.nvim_create_buf(false, true)
    table.insert(buffers, original_bufnr)
    table.insert(buffers, modified_bufnr)

    package.loaded['codediff.ui.lifecycle'] = {
      get_session = function()
        return { panel = { name = 'explorer' } }
      end,
      get_buffers = function()
        error('buffers exploded')
      end,
      get_paths = function()
        return { absolute = '/repo/original.lua' }, { absolute = '/repo/modified.lua' }
      end,
      get_windows = function()
        error('windows exploded')
      end,
      get_panel_view = function()
        error('panel view exploded')
      end,
      get_git_context = function()
        error('git context exploded')
      end,
    }

    assert.has_no.errors(run_check)

    assert.is_true(contains('error', 'Failed to inspect codediff buffers'))
    assert.is_true(contains('error', 'buffers exploded'))
    assert.is_true(contains('info', 'modified=/repo/modified.lua'))
    assert.is_true(contains('error', 'Failed to inspect the codediff panel view'))
    assert.is_false(contains('info', 'root='))
  end)

  it('reports an empty session with no usable sides', function()
    package.loaded['codediff.ui.lifecycle'] = {
      get_session = function()
        return {}
      end,
    }

    run_check()

    assert.is_true(contains('ok', 'Active codediff session found'))
    assert.is_true(contains('info', 'panel=none (bare diff)'))
    assert.is_true(contains('error', 'original buffer/path unavailable'))
    assert.is_true(contains('error', 'modified buffer/path unavailable'))
    assert.is_false(contains('info', 'Legacy session fields'))
  end)

  it('reports invalid configuration without replacing it', function()
    local config = require('staged.config')
    local invalid_options = vim.deepcopy(config.options)
    invalid_options.sidebar.width = 0
    config.options = invalid_options

    run_check()

    assert.is_true(contains('error', 'Current configuration is invalid'))
    assert.equals(invalid_options, config.options)
  end)

  it('reports a supported codediff version', function()
    stub_codediff_version('4.0.5')

    run_check()

    assert.is_true(contains('ok', 'codediff.nvim 4.0.5 is supported'))
  end)

  it('reports an unsupported older codediff version', function()
    stub_codediff_version('3.9.9')

    run_check()

    assert.is_true(contains('error', 'codediff.nvim 3.9.9 is too old'))
  end)

  it('reports an unsupported newer major codediff version', function()
    stub_codediff_version('5.0.0')

    run_check()

    assert.is_true(contains('error', 'codediff.nvim 5.0.0 is too new'))
  end)

  it('reports an unrecognized codediff version as a warning, not a crash', function()
    stub_codediff_version('not-a-version')

    run_check()

    assert.is_true(contains('warn', 'unrecognized version "not-a-version"'))
    assert.is_false(contains('error', 'unrecognized version'))
  end)

  it('reports a throwing codediff.version require as a warning, not a crash', function()
    stub_codediff_version(nil, 'version module exploded')

    run_check()

    assert.is_true(contains('warn', 'Could not determine the codediff.nvim version'))
    assert.is_false(contains('error', 'Could not determine the codediff.nvim version'))
  end)

  it('reports a codediff.version module without VERSION as a warning, not a crash', function()
    stub_codediff_version(nil)

    run_check()

    assert.is_true(contains('warn', 'Could not determine the codediff.nvim version'))
  end)

  it('never reports a missing clipboard provider as a failure', function()
    vim.fn.has = function(feature)
      return feature == 'clipboard' and 0 or original_has(feature)
    end

    run_check()

    assert.is_true(contains('info', 'No clipboard provider detected'))
    assert.is_false(contains('error', 'clipboard provider'))
    assert.is_false(contains('warn', 'clipboard provider'))
  end)
end)
