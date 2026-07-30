local helpers = require('tests.helpers')

describe('feature configuration', function()
  local config = require('staged.config')
  local original_options

  before_each(function()
    original_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = original_options
  end)

  it('validates documented enum options atomically', function()
    local cases = {
      { 'activation.mode', { activation = { mode = 'sometimes' } } },
      { 'sidebar.position', { sidebar = { position = 'top' } } },
      { 'inline.style', { inline = { style = 'conceal' } } },
      { 'input.style', { input = { style = 'popup' } } },
      { 'export.format', { export = { format = 'json' } } },
    }

    for _, case in ipairs(cases) do
      local before = vim.deepcopy(config.options)
      local ok, err = pcall(config.setup, case[2])

      assert.is_false(ok)
      assert.is_not_nil(tostring(err):find(case[1], 1, true))
      assert.same(before, config.options)
    end
  end)

  it('requires positive integer sidebar dimensions', function()
    local cases = {
      { 'sidebar.width', { sidebar = { width = 0 } } },
      { 'sidebar.width', { sidebar = { width = 1.5 } } },
      { 'sidebar.height', { sidebar = { height = -1 } } },
    }

    for _, case in ipairs(cases) do
      local ok, err = pcall(config.setup, case[2])

      assert.is_false(ok)
      assert.is_not_nil(tostring(err):find(case[1], 1, true))
    end
  end)

  it('validates values that are passed to Neovim APIs', function()
    local cases = {
      { 'sidebar.auto_show', { sidebar = { auto_show = 'yes' } } },
      { 'export.include_code', { export = { include_code = 1 } } },
      { 'keymaps.next_comment', { keymaps = { next_comment = '' } } },
      { 'inline.sign_icon', { inline = { sign_icon = 'wide' } } },
      { 'inline.virtual_text_format', { inline = { virtual_text_format = '%d %d' } } },
    }

    for _, case in ipairs(cases) do
      local ok, err = pcall(config.setup, case[2])

      assert.is_false(ok)
      assert.is_not_nil(tostring(err):find(case[1], 1, true))
    end
  end)
end)

describe('comment input', function()
  local config = require('staged.config')
  local input = require('staged.ui.input')
  local original_options
  local original_ui_input
  local input_buf
  local input_win

  before_each(function()
    original_options = vim.deepcopy(config.options)
    original_ui_input = vim.ui.input
  end)

  after_each(function()
    config.options = original_options
    vim.ui.input = original_ui_input
    vim.cmd('stopinsert')

    if input_win and vim.api.nvim_win_is_valid(input_win) then
      vim.api.nvim_win_close(input_win, true)
    end
    if input_buf and vim.api.nvim_buf_is_valid(input_buf) then
      vim.api.nvim_buf_delete(input_buf, { force = true })
    end
  end)

  it('uses vim.ui.input for inline input', function()
    local ui_opts
    local result
    vim.ui.input = function(opts, callback)
      ui_opts = opts
      callback('  updated comment  ')
    end
    config.options.input.style = 'inline'

    input.open({ title = 'Edit Comment', initial_text = 'old comment' }, function(text)
      result = text
    end)

    assert.equals('Edit Comment: ', ui_opts.prompt)
    assert.equals('old comment', ui_opts.default)
    assert.equals('updated comment', result)
  end)

  it('normalizes empty inline input to cancellation', function()
    local result = false
    vim.ui.input = function(_, callback)
      callback('   ')
    end

    input.open_inline({ title = 'Add Comment' }, function(text)
      result = text
    end)

    assert.is_nil(result)
  end)

  it('closes floating input before invoking its callback', function()
    local result = false
    local callback_count = 0
    local was_open_during_callback

    input.open_floating({ title = 'Add Comment', initial_text = 'first\nsecond' }, function(text)
      callback_count = callback_count + 1
      result = text
      was_open_during_callback = vim.api.nvim_win_is_valid(input_win)
    end)

    input_buf = vim.api.nvim_get_current_buf()
    input_win = vim.api.nvim_get_current_win()

    assert.equals('FloatBorder:StagedInputBorder', vim.wo[input_win].winhighlight)
    assert.is_not_nil(vim.fn.maparg('<Esc>', 'n', false, true).callback)
    local escape = vim.fn.maparg('<Esc>', 'i', false, true)
    assert.is_not_nil(escape.callback)
    escape.callback()

    assert.equals(1, callback_count)
    assert.is_nil(result)
    assert.is_false(was_open_during_callback)
  end)

  it('preserves multiline floating input when saved', function()
    local result
    input.open_floating({ title = 'Edit Comment', initial_text = ' first\nsecond ' }, function(text)
      result = text
    end)

    input_buf = vim.api.nvim_get_current_buf()
    input_win = vim.api.nvim_get_current_win()
    local save = vim.fn.maparg('<C-s>', 'i', false, true)
    save.callback()

    assert.equals('first\nsecond', result)
  end)
end)

describe('export features', function()
  local config = require('staged.config')
  local state = require('staged.core.state')
  local comments = require('staged.core.comments')
  local formatter = require('staged.export.formatter')
  local destinations = require('staged.export.destinations')
  local original_options
  local original_notify
  local original_io_open
  local test_buf
  local session
  local created_tabs
  local created_files

  before_each(function()
    original_options = vim.deepcopy(config.options)
    original_notify = vim.notify
    original_io_open = io.open
    created_tabs = {}
    created_files = {}

    test_buf = helpers.create_test_buffer(helpers.default_lines)
    session = helpers.create_mock_session(test_buf, '/test/example.lua')
  end)

  after_each(function()
    config.options = original_options
    vim.notify = original_notify
    io.open = original_io_open

    for i = #created_tabs, 1, -1 do
      local tabpage = created_tabs[i]
      if vim.api.nvim_tabpage_is_valid(tabpage) then
        vim.api.nvim_set_current_tabpage(tabpage)
        vim.cmd('tabclose!')
      end
    end
    for _, path in ipairs(created_files) do
      vim.fn.delete(path)
    end

    helpers.cleanup_session()
    if vim.api.nvim_buf_is_valid(test_buf) then
      vim.api.nvim_buf_delete(test_buf, { force = true })
    end
  end)

  it('formats plain output with indented code', function()
    comments.add(3, 4, 'check implementation', session)
    local relative_path = vim.fn.fnamemodify('/test/example.lua', ':~:.')

    local output = formatter.format(session, { format = 'plain', include_code = true })

    assert.equals(
      table.concat({
        relative_path,
        '',
        'Lines 3-4: check implementation',
        '    function M.hello()',
        '      print("hello")',
        '',
      }, '\n'),
      output
    )
    assert.is_nil(output:find('```', 1, true))
    assert.is_nil(output:find('**', 1, true))
  end)

  it('honors an explicit format over configuration', function()
    config.options.export.format = 'plain'
    comments.add(3, 3, 'markdown override', session)

    local output = formatter.format(session, { format = 'markdown', include_code = false })

    assert.equals('## ', output:sub(1, 3))
    assert.is_not_nil(output:find('**Line 3**', 1, true))
  end)

  it('formats the passed session instead of the current session', function()
    comments.add(3, 3, 'current session', session)

    local passed_buf = helpers.create_test_buffer({ 'passed session code' })
    local passed_path = '/test/passed.txt'
    local passed_session = {
      tabpage = -1,
      files = {},
      current_file = nil,
      ns_id = vim.api.nvim_create_namespace('staged-passed-session'),
      indicator_ns_id = vim.api.nvim_create_namespace('staged-passed-session-indicators'),
      keymaps = {},
    }
    state.set_current_file(passed_session, passed_path, passed_buf)
    comments.add(1, 1, 'passed session', passed_session)

    local output = formatter.format(passed_session, { include_code = false })

    assert.is_not_nil(output:find('passed session', 1, true))
    assert.is_nil(output:find('current session', 1, true))
    vim.api.nvim_buf_delete(passed_buf, { force = true })
  end)

  it('creates uniquely named buffers with matching filetypes', function()
    destinations.to_buffer('plain export', 'plain')
    local plain_buf = vim.api.nvim_get_current_buf()
    local plain_name = vim.api.nvim_buf_get_name(plain_buf)
    table.insert(created_tabs, vim.api.nvim_get_current_tabpage())

    destinations.to_buffer('# markdown export', 'markdown')
    local markdown_buf = vim.api.nvim_get_current_buf()
    local markdown_name = vim.api.nvim_buf_get_name(markdown_buf)
    table.insert(created_tabs, vim.api.nvim_get_current_tabpage())

    assert.equals('text', vim.bo[plain_buf].filetype)
    assert.equals('markdown', vim.bo[markdown_buf].filetype)
    assert.not_equals(plain_name, markdown_name)
  end)

  it('reports write and close failures', function()
    local notifications = {}
    vim.notify = function(message, level)
      table.insert(notifications, { message = message, level = level })
    end

    local closed_after_write_failure = false
    io.open = function()
      return {
        write = function()
          return nil, 'disk full'
        end,
        close = function()
          closed_after_write_failure = true
          return true
        end,
      }
    end
    destinations.to_file('content', '/tmp/staged-write-failure')

    io.open = function()
      local file = {}
      file.write = function()
        return file
      end
      file.close = function()
        return nil, 'close failed'
      end
      return file
    end
    destinations.to_file('content', '/tmp/staged-close-failure')

    assert.is_true(closed_after_write_failure)
    assert.equals(vim.log.levels.ERROR, notifications[1].level)
    assert.is_not_nil(notifications[1].message:find('disk full', 1, true))
    assert.equals(vim.log.levels.ERROR, notifications[2].level)
    assert.is_not_nil(notifications[2].message:find('close failed', 1, true))
  end)

  it('writes an export file', function()
    local path = vim.fn.tempname()
    table.insert(created_files, path)
    local notification
    vim.notify = function(message)
      notification = message
    end

    destinations.to_file('first\nsecond', path)

    assert.same({ 'first', 'second' }, vim.fn.readfile(path))
    assert.is_not_nil(notification:find(path, 1, true))
  end)
end)
