local helpers = require('tests.helpers')

describe('comment history', function()
  local state = require('staged.core.state')
  local comments = require('staged.core.comments')
  local staged = require('staged')

  local buffers
  local session

  before_each(function()
    buffers = {
      helpers.create_test_buffer(helpers.default_lines),
    }
    session = helpers.create_mock_session(buffers[1], '/test/first.lua')
  end)

  after_each(function()
    helpers.cleanup_session()
    for _, buf in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
  end)

  it('undoes and redoes additions with position tracking intact', function()
    local comment = comments.add(3, 5, 'review this')
    local file_state = state.get_current_file_state(session)

    assert.is_true(staged.undo())
    assert.is_nil(file_state.comments[comment.id])

    assert.is_true(staged.redo())
    local restored = file_state.comments[comment.id]
    assert.equals('review this', restored.text)
    assert.is_not_nil(restored.extmark_id)
    assert.same(
      { 3, 5 },
      { require('staged.core.position').get_current_lines(session, file_state, restored) }
    )
  end)

  it('undoes and redoes edits and deletions', function()
    local comment = comments.add(3, 3, 'original')
    comments.edit(comment.id, 'updated')

    assert.is_true(staged.undo())
    assert.equals('original', comments.get_at_line(3, session).text)
    assert.is_true(staged.redo())
    assert.equals('updated', comments.get_at_line(3, session).text)

    comments.delete(comment.id)
    assert.equals(0, comments.count(session))
    assert.is_true(staged.undo())
    assert.equals('updated', comments.get_at_line(3, session).text)
  end)

  it('tracks deleted positions through buffer edits before undo', function()
    local comment = comments.add(3, 3, 'deleted')
    comments.delete(comment.id)
    vim.api.nvim_buf_set_lines(buffers[1], 0, 0, false, { 'inserted' })

    assert.is_true(staged.undo())
    local file_state = state.get_current_file_state(session)
    local restored = file_state.comments[comment.id]
    assert.same(
      { 4, 4 },
      { require('staged.core.position').get_current_lines(session, file_state, restored) }
    )
  end)

  it('tracks undone additions through buffer edits before redo', function()
    local comment = comments.add(3, 3, 'undone')
    assert.is_true(staged.undo())
    vim.api.nvim_buf_set_lines(buffers[1], 0, 0, false, { 'inserted' })

    assert.is_true(staged.redo())
    local file_state = state.get_current_file_state(session)
    local restored = file_state.comments[comment.id]
    assert.same(
      { 4, 4 },
      { require('staged.core.position').get_current_lines(session, file_state, restored) }
    )
  end)

  it('preserves live extmark positions when restoring older metadata', function()
    local comment = comments.add(3, 3, 'original')
    comments.edit(comment.id, 'updated')
    vim.api.nvim_buf_set_lines(buffers[1], 0, 0, false, { 'inserted' })

    assert.is_true(staged.undo())
    local file_state = state.get_current_file_state(session)
    local restored = file_state.comments[comment.id]
    assert.equals('original', restored.text)
    assert.same(
      { 4, 4 },
      { require('staged.core.position').get_current_lines(session, file_state, restored) }
    )
  end)

  it('restores a clear across every file in the session', function()
    local first = comments.add(2, 2, 'first file')
    local second_buf = helpers.create_test_buffer(helpers.default_lines)
    table.insert(buffers, second_buf)
    state.set_current_file(session, '/test/second.lua', second_buf)
    local second = comments.add(7, 8, 'second file')

    comments.clear_all(session)
    assert.equals(0, comments.total_count(session))

    assert.is_true(staged.undo())
    assert.equals(2, comments.total_count(session))
    assert.equals('first file', session.files['/test/first.lua'].comments[first.id].text)
    assert.equals('second file', session.files['/test/second.lua'].comments[second.id].text)
  end)

  it('invalidates redo history after a new change', function()
    comments.add(2, 2, 'first')
    assert.is_true(staged.undo())
    assert.equals(1, helpers.count_extmarks(buffers[1], session.history_ns_id))

    comments.add(4, 4, 'replacement')
    assert.is_false(staged.redo())
    assert.equals(1, comments.total_count(session))
    assert.equals(0, helpers.count_extmarks(buffers[1], session.history_ns_id))
  end)

  it('migrates dormant anchors to a replacement file buffer', function()
    local comment = comments.add(3, 3, 'migrated')
    comments.delete(comment.id)

    local replacement = helpers.create_test_buffer(helpers.default_lines)
    table.insert(buffers, replacement)
    state.set_current_file(session, '/test/first.lua', replacement)
    vim.api.nvim_buf_set_lines(replacement, 0, 0, false, { 'inserted' })

    assert.is_true(staged.undo())
    local file_state = state.get_current_file_state(session)
    local restored = file_state.comments[comment.id]
    assert.same(
      { 4, 4 },
      { require('staged.core.position').get_current_lines(session, file_state, restored) }
    )
  end)

  it('creates dormant anchors when an unloaded file gets a replacement buffer', function()
    local comment = comments.add(3, 3, 'unloaded')
    vim.api.nvim_buf_delete(buffers[1], { force = true })
    comments.delete(comment.id)

    local replacement = helpers.create_test_buffer(helpers.default_lines)
    table.insert(buffers, replacement)
    state.set_current_file(session, '/test/first.lua', replacement)
    vim.api.nvim_buf_set_lines(replacement, 0, 0, false, { 'inserted' })

    assert.is_true(staged.undo())
    local file_state = state.get_current_file_state(session)
    local restored = file_state.comments[comment.id]
    assert.same(
      { 4, 4 },
      { require('staged.core.position').get_current_lines(session, file_state, restored) }
    )
  end)
end)

describe('comment events', function()
  local state = require('staged.core.state')
  local comments = require('staged.core.comments')

  local buf
  local session
  local group
  local records

  before_each(function()
    buf = helpers.create_test_buffer(helpers.default_lines)
    session = helpers.create_mock_session(buf, '/test/events.lua')
    records = {}
    group = vim.api.nvim_create_augroup('staged-test-events', { clear = true })
    vim.api.nvim_create_autocmd('User', {
      group = group,
      pattern = {
        'StagedCommentAdded',
        'StagedCommentEdited',
        'StagedCommentDeleted',
        'StagedCommentsCleared',
        'StagedCommentsChanged',
      },
      callback = function(args)
        table.insert(records, {
          match = args.match,
          data = args.data,
        })
      end,
    })
  end)

  after_each(function()
    pcall(vim.api.nvim_del_augroup_by_id, group)
    helpers.cleanup_session()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end)

  local function find(pattern, action)
    for _, record in ipairs(records) do
      if record.match == pattern and (not action or record.data.action == action) then
        return record.data
      end
    end
  end

  it('emits immutable public payloads for every mutation', function()
    local comment = comments.add(2, 3, 'first')
    comments.edit(comment.id, 'updated')
    comments.delete(comment.id)
    comments.add(5, 5, 'clear me')
    comments.clear_all(session)

    local added = find('StagedCommentAdded', 'add')
    assert.equals(session.tabpage, added.tabpage)
    assert.equals(comment.id, added.comment_id)
    assert.equals('/test/events.lua', added.file_path)
    assert.is_nil(added.comment.extmark_id)

    assert.is_not_nil(find('StagedCommentEdited', 'edit'))
    assert.is_not_nil(find('StagedCommentDeleted', 'delete'))
    local cleared = find('StagedCommentsCleared', 'clear_all')
    assert.equals(1, cleared.count)
    assert.equals('session', cleared.scope)
    assert.equals(0, find('StagedCommentsChanged', 'clear_all').total_count)
  end)

  it('keeps paired event ordering stable during reentrant mutations', function()
    local sequence = {}
    vim.api.nvim_create_autocmd('User', {
      group = group,
      pattern = {
        'StagedCommentAdded',
        'StagedCommentDeleted',
        'StagedCommentsChanged',
      },
      callback = function(args)
        table.insert(sequence, {
          match = args.match,
          action = args.data.action,
          total_count = args.data.total_count,
        })
      end,
    })
    vim.api.nvim_create_autocmd('User', {
      group = group,
      pattern = 'StagedCommentAdded',
      callback = function(args)
        comments.delete(args.data.comment_id, session)
      end,
    })

    comments.add(2, 2, 'reentrant')

    assert.same({
      { match = 'StagedCommentAdded', action = 'add', total_count = 1 },
      { match = 'StagedCommentsChanged', action = 'add', total_count = 1 },
      { match = 'StagedCommentDeleted', action = 'delete', total_count = 0 },
      { match = 'StagedCommentsChanged', action = 'delete', total_count = 0 },
    }, sequence)
  end)
end)
