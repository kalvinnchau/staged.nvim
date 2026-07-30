local helpers = require('tests.helpers')

describe('overlapping comment selection', function()
  local staged = require('staged')
  local state = require('staged.core.state')
  local comments = require('staged.core.comments')
  local input = require('staged.ui.input')

  local test_buf
  local session
  local original_select
  local original_input_open
  local extra_buffers
  local extra_groups

  before_each(function()
    test_buf = helpers.create_test_buffer(helpers.default_lines)
    session = helpers.create_mock_session(test_buf, '/test/selection.lua')
    vim.api.nvim_set_current_buf(test_buf)
    original_select = vim.ui.select
    original_input_open = input.open
    extra_buffers = {}
    extra_groups = {}
  end)

  after_each(function()
    vim.ui.select = original_select
    input.open = original_input_open
    state.destroy_session(session.tabpage)
    if vim.api.nvim_buf_is_valid(test_buf) then
      vim.api.nvim_buf_delete(test_buf, { force = true })
    end
    for _, buf in ipairs(extra_buffers) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    for _, group in ipairs(extra_groups) do
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end
  end)

  it('returns every current range match in deterministic order', function()
    local outer = comments.add(2, 6, 'outer', session)
    local short = comments.add(3, 4, 'short', session)
    local long = comments.add(3, 5, 'long', session)

    vim.api.nvim_buf_set_lines(test_buf, 0, 0, false, { 'inserted' })

    local matches = comments.get_all_at_line(4, session)
    assert.same({ outer, short, long }, matches)
    assert.equals(outer, comments.get_at_line(4, session))
    assert.same({}, comments.get_all_at_line(1, session))
  end)

  it('edits a single match without opening a selector', function()
    local comment = comments.add(3, 3, 'original', session)
    local select_calls = 0
    vim.ui.select = function()
      select_calls = select_calls + 1
    end
    input.open = function(opts, callback)
      assert.equals('original', opts.initial_text)
      callback('edited')
    end
    vim.api.nvim_win_set_cursor(0, { 3, 0 })

    staged.edit_comment_at_cursor()

    assert.equals(0, select_calls)
    assert.equals('edited', comment.text)
  end)

  it('edits the selected overlapping comment after the cursor moves', function()
    local first = comments.add(2, 5, 'first comment', session)
    local second = comments.add(3, 4, 'second\n  comment', session)
    local choose
    vim.ui.select = function(items, opts, callback)
      assert.same({ first, second }, items)
      assert.equals('L3-4  second comment', opts.format_item(second))
      choose = function()
        callback(items[2])
      end
    end
    input.open = function(opts, callback)
      assert.equals(second.text, opts.initial_text)
      callback('edited second')
    end
    vim.api.nvim_win_set_cursor(0, { 3, 0 })

    staged.edit_comment_at_cursor()
    vim.api.nvim_win_set_cursor(0, { 8, 0 })
    choose()

    assert.equals('first comment', first.text)
    assert.equals('edited second', second.text)
  end)

  it('deletes only the selected overlapping comment', function()
    local first = comments.add(2, 5, 'first', session)
    local second = comments.add(3, 4, 'second', session)
    local choose
    vim.ui.select = function(items, _, callback)
      choose = function()
        callback(items[2])
      end
    end
    vim.api.nvim_win_set_cursor(0, { 3, 0 })

    staged.delete_comment_at_cursor()
    vim.api.nvim_win_set_cursor(0, { 8, 0 })
    choose()

    local file_state = state.get_current_file_state(session)
    assert.equals(first, file_state.comments[first.id])
    assert.is_nil(file_state.comments[second.id])
  end)

  it('does nothing when overlapping selection is cancelled', function()
    local first = comments.add(2, 5, 'first', session)
    local second = comments.add(3, 4, 'second', session)
    local input_calls = 0
    vim.ui.select = function(_, _, callback)
      callback(nil)
    end
    input.open = function()
      input_calls = input_calls + 1
    end
    vim.api.nvim_win_set_cursor(0, { 3, 0 })

    staged.edit_comment_at_cursor()
    staged.delete_comment_at_cursor()

    assert.equals(0, input_calls)
    assert.equals(2, comments.count(session))
    assert.equals('first', first.text)
    assert.equals('second', second.text)
  end)

  it('ignores an asynchronous choice after its session closes', function()
    local first = comments.add(2, 5, 'first', session)
    local second = comments.add(3, 4, 'second', session)
    local choose
    local input_calls = 0
    vim.ui.select = function(items, _, callback)
      choose = function()
        callback(items[2])
      end
    end
    input.open = function()
      input_calls = input_calls + 1
    end
    vim.api.nvim_win_set_cursor(0, { 3, 0 })

    staged.edit_comment_at_cursor()
    state.destroy_session(session.tabpage)
    choose()

    assert.equals(0, input_calls)
    assert.equals('first', first.text)
    assert.equals('second', second.text)
  end)

  it('ignores asynchronous input after its session closes', function()
    local submit
    input.open = function(_, callback)
      submit = callback
    end
    vim.api.nvim_win_set_cursor(0, { 3, 0 })

    staged.add_comment_interactive()
    state.destroy_session(session.tabpage)
    submit('late comment')

    assert.equals(0, vim.tbl_count(session.files['/test/selection.lua'].comments))
    assert.equals(0, helpers.count_extmarks(test_buf, session.ns_id))
  end)

  it('does not attach asynchronous input to a newly selected file', function()
    local submit
    input.open = function(_, callback)
      submit = callback
    end
    vim.api.nvim_win_set_cursor(0, { 3, 0 })

    staged.add_comment_interactive()
    local second_buf = helpers.create_test_buffer(helpers.default_lines)
    table.insert(extra_buffers, second_buf)
    state.set_current_file(session, '/test/second.lua', second_buf)
    submit('wrong file')

    assert.equals(0, vim.tbl_count(session.files['/test/selection.lua'].comments))
    assert.equals(0, vim.tbl_count(session.files['/test/second.lua'].comments))
  end)

  it('does not attach asynchronous input to a replacement buffer', function()
    local submit
    input.open = function(_, callback)
      submit = callback
    end
    vim.api.nvim_win_set_cursor(0, { 3, 0 })

    staged.add_comment_interactive()
    local replacement = helpers.create_test_buffer(helpers.default_lines)
    table.insert(extra_buffers, replacement)
    state.set_current_file(session, '/test/selection.lua', replacement)
    submit('wrong buffer')

    assert.equals(0, vim.tbl_count(session.files['/test/selection.lua'].comments))
  end)

  it('does not recreate ui after an event destroys the session', function()
    input.open = function(_, callback)
      callback('destroy session')
    end
    local group = vim.api.nvim_create_augroup('staged-test-destroy-on-add', { clear = true })
    table.insert(extra_groups, group)
    vim.api.nvim_create_autocmd('User', {
      group = group,
      pattern = 'StagedCommentAdded',
      once = true,
      callback = function()
        state.destroy_session(session.tabpage)
      end,
    })
    vim.api.nvim_win_set_cursor(0, { 3, 0 })

    staged.add_comment_interactive()

    assert.is_nil(state.get_session(session.tabpage))
    assert.equals(0, helpers.count_extmarks(test_buf, session.indicator_ns_id))
    assert.is_false(
      session.sidebar_bufnr ~= nil and vim.api.nvim_buf_is_valid(session.sidebar_bufnr)
    )
  end)
end)
