describe('health', function()
  local original_health
  local original_lifecycle
  local original_lifecycle_preload
  local original_options
  local original_has
  local records
  local buffers

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

  before_each(function()
    original_health = vim.health
    original_lifecycle = package.loaded['codediff.ui.lifecycle']
    original_lifecycle_preload = package.preload['codediff.ui.lifecycle']
    original_options = require('staged.config').options
    original_has = vim.fn.has
    records = {}
    buffers = {}

    vim.health = {}
    for _, level in ipairs({ 'start', 'ok', 'info', 'warn', 'error' }) do
      vim.health[level] = function(message)
        table.insert(records, { level = level, message = message })
      end
    end
  end)

  after_each(function()
    vim.health = original_health
    package.loaded['codediff.ui.lifecycle'] = original_lifecycle
    package.preload['codediff.ui.lifecycle'] = original_lifecycle_preload
    package.loaded['staged.health'] = nil
    require('staged.config').options = original_options
    vim.fn.has = original_has

    for _, bufnr in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
  end)

  it('reports supported runtime, configuration, and an active codediff session', function()
    local original_bufnr = vim.api.nvim_create_buf(false, true)
    local modified_bufnr = vim.api.nvim_create_buf(false, true)
    table.insert(buffers, original_bufnr)
    table.insert(buffers, modified_bufnr)

    local tabpage = vim.api.nvim_get_current_tabpage()
    package.loaded['codediff.ui.lifecycle'] = {
      get_session = function(requested_tabpage)
        if requested_tabpage == tabpage then
          return {
            mode = 'explorer',
            layout = 'side-by-side',
            git_root = '/repo',
          }
        end
      end,
      get_buffers = function()
        return original_bufnr, modified_bufnr
      end,
      get_paths = function()
        return { absolute = '/repo/original.lua' }, { absolute = '/repo/modified.lua' }
      end,
    }

    run_check()

    assert.is_true(contains('ok', 'is supported'))
    assert.is_true(contains('ok', 'Current configuration is valid'))
    assert.is_true(contains('ok', 'Active codediff session found'))
    assert.is_true(contains('info', 'modified=' .. modified_bufnr))
    assert.is_true(contains('info', 'modified=/repo/modified.lua'))
  end)

  it('is robust when codediff is absent', function()
    package.loaded['codediff.ui.lifecycle'] = nil
    package.preload['codediff.ui.lifecycle'] = function()
      error('not installed')
    end

    assert.has_no.errors(run_check)
    assert.is_true(contains('error', 'codediff lifecycle is unavailable'))
  end)

  it('reports missing lifecycle accessors', function()
    package.loaded['codediff.ui.lifecycle'] = {
      get_session = function()
        return nil
      end,
    }

    run_check()

    assert.is_true(contains('info', 'get_buffers() is unavailable'))
    assert.is_true(contains('info', 'get_paths() is unavailable'))
    assert.is_true(contains('info', 'No active codediff session'))
  end)

  it('accepts legacy session buffer and path fields', function()
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

    assert.is_true(contains('info', 'modified=' .. modified_bufnr))
    assert.is_true(contains('info', 'modified=/repo/modified.lua'))
    assert.is_false(contains('error', 'No usable'))
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
