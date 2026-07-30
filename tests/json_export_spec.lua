local helpers = require('tests.helpers')

describe('json export', function()
  local config = require('staged.config')
  local state = require('staged.core.state')
  local comments = require('staged.core.comments')
  local formatter = require('staged.export.formatter')
  local destinations = require('staged.export.destinations')
  local original_options
  local source_tab
  local session
  local buffers
  local export_tabs
  local original_cwd

  before_each(function()
    original_options = vim.deepcopy(config.options)
    original_cwd = vim.fn.getcwd()
    source_tab = vim.api.nvim_get_current_tabpage()
    buffers = {}
    export_tabs = {}

    local buf = helpers.create_test_buffer({ 'zeta one', 'zeta two' })
    table.insert(buffers, buf)
    session = helpers.create_mock_session(buf, vim.fn.getcwd() .. '/zeta.lua')
  end)

  after_each(function()
    config.options = original_options
    vim.cmd('lcd ' .. vim.fn.fnameescape(original_cwd))

    for i = #export_tabs, 1, -1 do
      local tabpage = export_tabs[i]
      if vim.api.nvim_tabpage_is_valid(tabpage) then
        vim.api.nvim_set_current_tabpage(tabpage)
        vim.cmd('tabclose!')
      end
    end

    state.destroy_session(source_tab)
    for _, buf in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
  end)

  it('accepts json as a configured format', function()
    config.setup({ export = { format = 'json' } })

    assert.equals('json', config.options.export.format)
  end)

  it('emits deterministic versioned records in file and line order', function()
    comments.add(2, 2, 'zeta comment', session)

    local alpha_buf = helpers.create_test_buffer({ 'alpha one', 'alpha two' })
    table.insert(buffers, alpha_buf)
    state.set_current_file(session, vim.fn.getcwd() .. '/alpha.lua', alpha_buf)
    comments.add(1, 2, 'alpha comment', session)

    local output = formatter.format(session, { format = 'json', include_code = true })

    assert.equals(output, formatter.format(session, { format = 'json', include_code = true }))
    assert.equals(
      '{"schema_version":1,"comments":['
        .. '{"path":"alpha.lua","start_line":1,"end_line":2,'
        .. '"text":"alpha comment","code":"alpha one\\nalpha two"},'
        .. '{"path":"zeta.lua","start_line":2,"end_line":2,'
        .. '"text":"zeta comment","code":"zeta two"}]}',
      output
    )

    local decoded = vim.json.decode(output)
    assert.equals(1, decoded.schema_version)
    assert.equals(2, #decoded.comments)
  end)

  it('omits code when disabled and honors an explicit override', function()
    config.options.export.format = 'json'
    config.options.export.include_code = false
    comments.add(1, 1, 'code toggle', session)

    local without_code = vim.json.decode(formatter.format(session))
    local with_code =
      vim.json.decode(formatter.format(session, { format = 'json', include_code = true }))

    assert.is_nil(without_code.comments[1].code)
    assert.equals('zeta one', with_code.comments[1].code)
  end)

  it('uses the stable session root after the window cwd changes', function()
    comments.add(1, 1, 'stable root', session)
    vim.cmd('lcd ' .. vim.fn.fnameescape(vim.fs.dirname(vim.fn.tempname())))

    local record = vim.json.decode(
      formatter.format(session, { format = 'json', include_code = false })
    ).comments[1]

    assert.equals('zeta.lua', record.path)
  end)

  it('validates public formatter options', function()
    assert.has_error(function()
      formatter.format(session, false)
    end, 'staged.nvim: export options must be a table')
    assert.has_error(function()
      formatter.format(session, { format = 'yaml' })
    end, 'staged.nvim: export.format must be one of: markdown, plain, json')
    assert.has_error(function()
      formatter.format(session, { include_code = 'false' })
    end, 'staged.nvim: export.include_code must be a boolean')
  end)

  it('keeps creation order for comments with identical ranges and timestamps', function()
    local first = comments.add(1, 1, 'first', session)
    local second = comments.add(1, 1, 'second', session)
    second.created_at = first.created_at

    local records =
      vim.json.decode(formatter.format(session, { format = 'json', include_code = false })).comments

    assert.same({ 'first', 'second' }, { records[1].text, records[2].text })
  end)

  it('omits paths outside the session root and internal comment fields', function()
    local outside_path = vim.fn.tempname() .. '.lua'
    local outside_buf = helpers.create_test_buffer({ 'outside' })
    table.insert(buffers, outside_buf)
    state.set_current_file(session, outside_path, outside_buf)
    comments.add(1, 1, 'outside comment', session)

    local output = formatter.format(session, { format = 'json', include_code = false })
    local record = vim.json.decode(output).comments[1]

    assert.same({
      start_line = 1,
      end_line = 1,
      text = 'outside comment',
    }, record)
    assert.is_nil(output:find(outside_path, 1, true))
    assert.is_nil(output:find('extmark', 1, true))
  end)

  it('uses the json filetype for buffer exports', function()
    local content = '{"schema_version":1,"comments":[]}'
    destinations.to_buffer(content, 'json')
    table.insert(export_tabs, vim.api.nvim_get_current_tabpage())

    assert.equals('json', vim.bo.filetype)
    assert.same({ content }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)
end)
