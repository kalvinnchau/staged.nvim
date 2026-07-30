describe('codediff integration', function()
  local state = require('staged.core.state')
  local config = require('staged.config')
  local staged = require('staged')
  local original_lifecycle = package.loaded['codediff.ui.lifecycle']

  local codediff
  local lifecycle
  local codediff_session
  local tabpage
  local original_mode
  local original_bind_session_keymaps
  local buffers

  local function create_buffer()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'line' })
    table.insert(buffers, bufnr)
    return bufnr
  end

  local function reload_integration()
    package.loaded['codediff.ui.lifecycle'] = lifecycle
    package.loaded['staged.integration.codediff'] = nil
    codediff = require('staged.integration.codediff')
    codediff.setup_autocmds()
  end

  before_each(function()
    original_mode = config.options.activation.mode
    original_bind_session_keymaps = staged.bind_session_keymaps
    config.options.activation.mode = 'auto'
    tabpage = vim.api.nvim_get_current_tabpage()
    buffers = {}
    codediff_session = nil
    lifecycle = {
      get_session = function(requested_tabpage)
        if requested_tabpage == tabpage then
          return codediff_session
        end
      end,
    }
  end)

  after_each(function()
    pcall(vim.api.nvim_del_augroup_by_name, 'staged-codediff')

    local sessions = vim.tbl_keys(state.get_all_sessions())
    for _, session_tabpage in ipairs(sessions) do
      state.destroy_session(session_tabpage)
    end

    for _, bufnr in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end

    config.options.activation.mode = original_mode
    staged.bind_session_keymaps = original_bind_session_keymaps
    package.loaded['codediff.ui.lifecycle'] = original_lifecycle
    package.loaded['staged.integration.codediff'] = nil
  end)

  it('uses lifecycle accessors and Path.absolute for the modified file', function()
    local modified_bufnr = create_buffer()
    local bound_tabpage
    staged.bind_session_keymaps = function(requested_tabpage)
      bound_tabpage = requested_tabpage
    end
    codediff_session = {
      modified_bufnr = -1,
      modified_path = '/legacy.lua',
      stored_diff_result = {},
    }
    lifecycle.get_buffers = function()
      return 1, modified_bufnr
    end
    lifecycle.get_paths = function()
      return { absolute = '/repo/original.lua' }, { absolute = '/repo/modified.lua' }
    end
    reload_integration()

    local session = codediff.init_for_codediff(tabpage)

    assert.equals('/repo/modified.lua', session.current_file)
    assert.equals(modified_bufnr, state.get_current_bufnr(session))
    assert.equals(tabpage, bound_tabpage)
  end)

  it('supports legacy session buffer and path fields', function()
    local modified_bufnr = create_buffer()
    codediff_session = {
      modified_bufnr = modified_bufnr,
      modified_path = '/repo/legacy.lua',
    }
    reload_integration()

    local session = codediff.init_for_codediff(tabpage)

    assert.equals('/repo/legacy.lua', session.current_file)
    assert.equals(modified_bufnr, state.get_current_bufnr(session))
  end)

  it('creates automatically on CodeDiffOpen', function()
    local modified_bufnr = create_buffer()
    codediff_session = {
      git_root = '/repo',
      stored_diff_result = {},
    }
    lifecycle.get_buffers = function()
      return 1, modified_bufnr
    end
    lifecycle.get_paths = function()
      return { absolute = '/repo/original.lua' }, { absolute = '/repo/modified.lua' }
    end
    reload_integration()

    vim.api.nvim_exec_autocmds('User', {
      pattern = 'CodeDiffOpen',
      modeline = false,
      data = { tabpage = tabpage },
    })

    assert.is_true(vim.wait(500, function()
      return state.get_session(tabpage) ~= nil
    end))
  end)

  it('only syncs manual mode after a staged session exists', function()
    local modified_bufnr = create_buffer()
    codediff_session = {
      stored_diff_result = {},
    }
    lifecycle.get_buffers = function()
      return 1, modified_bufnr
    end
    lifecycle.get_paths = function()
      return '/repo/original.lua', '/repo/modified.lua'
    end
    config.options.activation.mode = 'manual'
    reload_integration()

    vim.api.nvim_exec_autocmds('User', {
      pattern = 'CodeDiffOpen',
      modeline = false,
      data = { tabpage = tabpage },
    })
    vim.api.nvim_exec_autocmds('BufWinEnter', { modeline = false })
    assert.is_nil(state.get_session(tabpage))

    local session = state.create_session(tabpage)
    vim.api.nvim_exec_autocmds('BufWinEnter', { modeline = false })

    assert.equals('/repo/modified.lua', session.current_file)
    assert.equals(modified_bufnr, state.get_current_bufnr(session))
  end)

  it('waits for the selected path and completed diff result', function()
    local old_bufnr = create_buffer()
    local new_bufnr = create_buffer()
    local modified_bufnr = old_bufnr
    local modified_ref = {
      relative = 'old.lua',
      absolute = '/repo/old.lua',
    }
    codediff_session = {
      git_root = '/repo',
      stored_diff_result = nil,
    }
    lifecycle.get_buffers = function()
      return 1, modified_bufnr
    end
    lifecycle.get_paths = function()
      return { absolute = '/repo/original.lua' }, modified_ref
    end
    config.options.activation.mode = 'manual'
    reload_integration()

    local session = state.create_session(tabpage)
    state.set_current_file(session, '/repo/old.lua', old_bufnr)

    vim.api.nvim_exec_autocmds('User', {
      pattern = 'CodeDiffFileSelect',
      modeline = false,
      data = {
        tabpage = tabpage,
        path = 'new.lua',
      },
    })

    modified_bufnr = new_bufnr
    modified_ref = {
      relative = 'new.lua',
      absolute = '/repo/new.lua',
    }
    vim.wait(75, function()
      return false
    end, 5)
    assert.equals('/repo/old.lua', session.current_file)

    modified_ref = {
      relative = 'old.lua',
      absolute = '/repo/old.lua',
    }
    codediff_session.stored_diff_result = {}
    vim.wait(75, function()
      return false
    end, 5)
    assert.equals('/repo/old.lua', session.current_file)

    modified_ref = {
      relative = 'new.lua',
      absolute = '/repo/new.lua',
    }
    assert.is_true(vim.wait(500, function()
      return session.current_file == '/repo/new.lua'
    end, 5))
    assert.equals(new_bufnr, state.get_current_bufnr(session))
  end)

  it('destroys the exact tab handle from CodeDiffClose', function()
    local other_tabpage = 999999
    local current_session = state.create_session(tabpage)
    state.create_session(other_tabpage)
    reload_integration()

    vim.api.nvim_exec_autocmds('User', {
      pattern = 'CodeDiffClose',
      modeline = false,
      data = { tabpage = other_tabpage },
    })

    assert.is_nil(state.get_session(other_tabpage))
    assert.equals(current_session, state.get_session(tabpage))
  end)

  it('removes sessions whose tab handles became invalid', function()
    config.options.activation.mode = 'manual'
    reload_integration()

    vim.cmd('tabnew')
    local closed_tabpage = vim.api.nvim_get_current_tabpage()
    state.create_session(closed_tabpage)
    vim.cmd('tabclose')

    assert.is_true(vim.wait(500, function()
      return state.get_session(closed_tabpage) == nil
    end))
  end)
end)
