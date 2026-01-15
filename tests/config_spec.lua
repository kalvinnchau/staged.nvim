local helpers = require('tests.helpers')

describe('config', function()
  local config = require('staged.config')
  local original_options

  before_each(function()
    -- Save original config
    original_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    -- Restore original config
    config.options = original_options
  end)

  describe('setup', function()
    it('should use defaults when no opts provided', function()
      config.setup()

      assert.equals('auto', config.options.activation.mode)
      assert.equals('<leader>c', config.options.keymaps.prefix)
      assert.equals(40, config.options.sidebar.width)
      assert.equals('sign', config.options.inline.style)
    end)

    it('should merge user options with defaults', function()
      config.setup({
        sidebar = { width = 60 },
        inline = { style = 'virtual_text' },
      })

      -- Changed values
      assert.equals(60, config.options.sidebar.width)
      assert.equals('virtual_text', config.options.inline.style)

      -- Unchanged defaults
      assert.equals('auto', config.options.activation.mode)
      assert.equals('<leader>c', config.options.keymaps.prefix)
    end)

    it('should allow changing keymap prefix', function()
      config.setup({
        keymaps = { prefix = '<leader>m' },
      })

      assert.equals('<leader>m', config.options.keymaps.prefix)
      -- Other keymaps unchanged
      assert.equals('i', config.options.keymaps.add)
    end)

    it('should allow disabling auto_show', function()
      config.setup({
        sidebar = { auto_show = false },
      })

      assert.is_false(config.options.sidebar.auto_show)
    end)
  end)
end)

describe('inline styles', function()
  local config = require('staged.config')
  local inline = require('staged.ui.inline')
  local highlights = require('staged.ui.highlights')
  local state = require('staged.core.state')

  local test_buf
  local session
  local original_options

  before_each(function()
    original_options = vim.deepcopy(config.options)
    test_buf = helpers.create_test_buffer(helpers.default_lines)
    session = helpers.create_mock_session(test_buf, '/test/file.lua')
  end)

  after_each(function()
    config.options = original_options
    helpers.cleanup_session()
    if vim.api.nvim_buf_is_valid(test_buf) then
      vim.api.nvim_buf_delete(test_buf, { force = true })
    end
  end)

  it('should render sign style', function()
    config.options.inline.style = 'sign'
    helpers.add_comment(3, 3, 'Sign comment')
    inline.render(session)

    local signs = helpers.get_signs(test_buf, 'staged')
    assert.equals(1, #signs)
  end)

  it('should render virtual_text style', function()
    config.options.inline.style = 'virtual_text'
    helpers.add_comment(3, 3, 'Virtual text comment')
    inline.render(session)

    -- Virtual text uses extmarks in the indicators namespace
    local marks =
      vim.api.nvim_buf_get_extmarks(test_buf, highlights.ns_indicators, 0, -1, { details = true })
    assert.equals(1, #marks)
    assert.is_not_nil(marks[1][4].virt_text)
  end)

  it('should render line_highlight style', function()
    config.options.inline.style = 'line_highlight'
    helpers.add_comment(3, 5, 'Highlighted lines')
    inline.render(session)

    -- Line highlight uses extmarks with line_hl_group
    local marks =
      vim.api.nvim_buf_get_extmarks(test_buf, highlights.ns_indicators, 0, -1, { details = true })
    -- Should have 3 marks for lines 3, 4, 5
    assert.equals(3, #marks)
  end)

  it('should use custom sign icon', function()
    config.options.inline.style = 'sign'
    config.options.inline.sign_icon = '!!'

    -- Re-setup highlights to pick up new icon
    highlights.setup()

    helpers.add_comment(3, 3, 'Custom icon')
    inline.render(session)

    local signs = helpers.get_signs(test_buf, 'staged')
    assert.equals(1, #signs)
  end)
end)

describe('sidebar position', function()
  local config = require('staged.config')
  local sidebar = require('staged.ui.sidebar')
  local state = require('staged.core.state')

  local test_buf
  local session
  local original_options

  before_each(function()
    original_options = vim.deepcopy(config.options)
    test_buf = helpers.create_test_buffer(helpers.default_lines)
    session = helpers.create_mock_session(test_buf, '/test/file.lua')
    vim.api.nvim_set_current_buf(test_buf)
  end)

  after_each(function()
    config.options = original_options
    if session.visible then
      sidebar.hide(session)
    end
    helpers.cleanup_session()
    if vim.api.nvim_buf_is_valid(test_buf) then
      vim.api.nvim_buf_delete(test_buf, { force = true })
    end
  end)

  it('should open on right when position is right', function()
    config.options.sidebar.position = 'right'
    helpers.add_comment(3, 3, 'Test')
    sidebar.show(session)

    assert.is_true(session.visible)
    assert.is_not_nil(session.sidebar_winid)

    -- Get window position info
    local win_col = vim.api.nvim_win_get_position(session.sidebar_winid)[2]
    local main_win = vim.fn.win_getid(1)
    local main_col = vim.api.nvim_win_get_position(main_win)[2]

    -- Sidebar should be to the right (higher column)
    assert.is_true(win_col >= main_col)
  end)

  it('should open on left when position is left', function()
    config.options.sidebar.position = 'left'
    helpers.add_comment(3, 3, 'Test')
    sidebar.show(session)

    assert.is_true(session.visible)
    assert.is_not_nil(session.sidebar_winid)
  end)

  it('should respect custom width', function()
    config.options.sidebar.width = 50
    helpers.add_comment(3, 3, 'Test')
    sidebar.show(session)

    local width = vim.api.nvim_win_get_width(session.sidebar_winid)
    assert.equals(50, width)
  end)
end)

describe('export options', function()
  local config = require('staged.config')
  local formatter = require('staged.export.formatter')
  local state = require('staged.core.state')

  local test_buf
  local session
  local original_options

  before_each(function()
    original_options = vim.deepcopy(config.options)
    test_buf = helpers.create_test_buffer(helpers.default_lines)
    session = helpers.create_mock_session(test_buf, '/test/file.lua')
  end)

  after_each(function()
    config.options = original_options
    helpers.cleanup_session()
    if vim.api.nvim_buf_is_valid(test_buf) then
      vim.api.nvim_buf_delete(test_buf, { force = true })
    end
  end)

  it('should include code when include_code is true', function()
    config.options.export.include_code = true
    helpers.add_comment(3, 3, 'With code')

    local output = formatter.format(session)

    assert.is_true(output:find('```') ~= nil)
    assert.is_true(output:find('M.hello') ~= nil)
  end)

  it('should exclude code when include_code is false', function()
    config.options.export.include_code = false
    helpers.add_comment(3, 3, 'Without code')

    local output = formatter.format(session)

    assert.is_nil(output:find('```'))
    assert.is_true(output:find('Without code') ~= nil)
  end)

  it('should override config with opts parameter', function()
    config.options.export.include_code = true
    helpers.add_comment(3, 3, 'Override test')

    -- Config says include, but opts says exclude
    local output = formatter.format(session, { include_code = false })

    assert.is_nil(output:find('```'))
  end)
end)

describe('activation mode', function()
  local config = require('staged.config')
  local original_options

  before_each(function()
    original_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = original_options
  end)

  it('should allow auto mode', function()
    config.setup({ activation = { mode = 'auto' } })
    assert.equals('auto', config.options.activation.mode)
  end)

  it('should allow manual mode', function()
    config.setup({ activation = { mode = 'manual' } })
    assert.equals('manual', config.options.activation.mode)
  end)
end)
