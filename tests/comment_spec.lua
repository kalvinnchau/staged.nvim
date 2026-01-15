describe('comments', function()
  local state = require('staged.core.state')
  local comments = require('staged.core.comments')

  local test_buf
  local test_tabpage
  local test_path = '/test/file.lua'

  before_each(function()
    -- Create test buffer
    test_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
      'line 1',
      'line 2',
      'line 3',
      'line 4',
      'line 5',
    })

    -- Get current tabpage for session
    test_tabpage = vim.api.nvim_get_current_tabpage()

    -- Create session and set current file
    local session = state.create_session(test_tabpage)
    state.set_current_file(session, test_path, test_buf)
  end)

  after_each(function()
    state.destroy_session(test_tabpage)
    if vim.api.nvim_buf_is_valid(test_buf) then
      vim.api.nvim_buf_delete(test_buf, { force = true })
    end
  end)

  it('should add a comment', function()
    local c = comments.add(2, 3, 'Test comment')
    assert.is_not_nil(c)
    assert.equals('Test comment', c.text)
    assert.equals(2, c.start_line)
    assert.equals(3, c.end_line)
  end)

  it('should edit a comment', function()
    local c = comments.add(1, 1, 'Original')
    comments.edit(c.id, 'Updated')

    local session = state.get_current_session()
    local file_state = state.get_current_file_state(session)
    assert.equals('Updated', file_state.comments[c.id].text)
  end)

  it('should delete a comment', function()
    local c = comments.add(1, 1, 'Test')
    comments.delete(c.id)

    assert.equals(0, comments.count())
  end)

  it('should get sorted comments', function()
    comments.add(5, 5, 'Last')
    comments.add(1, 1, 'First')
    comments.add(3, 3, 'Middle')

    local sorted = comments.get_sorted()
    assert.equals(3, #sorted)
    assert.equals('First', sorted[1].text)
    assert.equals('Middle', sorted[2].text)
    assert.equals('Last', sorted[3].text)
  end)

  it('should get comment at line', function()
    comments.add(2, 4, 'Multi-line comment')

    local c = comments.get_at_line(3)
    assert.is_not_nil(c)
    assert.equals('Multi-line comment', c.text)

    local none = comments.get_at_line(1)
    assert.is_nil(none)
  end)

  it('should clear all comments', function()
    comments.add(1, 1, 'First')
    comments.add(2, 2, 'Second')
    comments.add(3, 3, 'Third')

    assert.equals(3, comments.count())

    comments.clear_all()

    assert.equals(0, comments.count())
  end)

  it('should generate unique ids', function()
    local c1 = comments.add(1, 1, 'First')
    local c2 = comments.add(2, 2, 'Second')

    assert.is_not_nil(c1.id)
    assert.is_not_nil(c2.id)
    assert.are_not.equals(c1.id, c2.id)
  end)
end)
