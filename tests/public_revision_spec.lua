local helpers = require('tests.helpers')

describe('revision-aware public API', function()
  local staged = require('staged')
  local state = require('staged.core.state')
  local comments = require('staged.core.comments')
  local input = require('staged.ui.input')
  local session
  local buffers
  local original_input
  local original_select

  before_each(function()
    buffers = {}
    original_input = input.open
    original_select = vim.ui.select
    session = state.create_session(vim.api.nvim_get_current_tabpage())
  end)

  after_each(function()
    input.open = original_input
    vim.ui.select = original_select
    state.destroy_session(session.tabpage)
    for _, buf in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
  end)

  local function select_revision(revision)
    local buf = helpers.create_test_buffer({ 'first', 'second', 'third' })
    table.insert(buffers, buf)
    state.set_current_file(session, '/test/review.lua', buf, {
      modified_revision = revision,
      original_revision = 'base',
    })
    vim.api.nvim_set_current_buf(buf)
    return buf
  end

  it('edits a comment on a virtual revision through the public API', function()
    select_revision('commit-a')
    local comment = comments.add(1, 1, 'before', session)
    input.open = function(_, callback)
      callback('after')
    end

    staged.edit_comment_at_cursor()

    assert.equals('after', comment.text)
  end)

  it('keeps asynchronous overlapping selection attached to its revision', function()
    select_revision(':0')
    local first = comments.add(1, 2, 'first index comment', session)
    local second = comments.add(1, 3, 'second index comment', session)
    local choose
    vim.ui.select = function(items, _, callback)
      choose = function()
        callback(items[2])
      end
    end
    input.open = function(_, callback)
      callback('edited index comment')
    end
    staged.edit_comment_at_cursor()

    select_revision('WORKING')
    local working = comments.add(1, 1, 'working comment', session)
    choose()

    assert.equals('first index comment', first.text)
    assert.equals('edited index comment', second.text)
    assert.equals('working comment', working.text)
  end)

  it('does not add delayed input to a different revision of the same path', function()
    select_revision(':0')
    local submit
    input.open = function(_, callback)
      submit = callback
    end
    staged.add_comment_interactive()
    select_revision('WORKING')
    submit('late comment')

    assert.equals(0, state.total_comment_count(session))
  end)
end)
