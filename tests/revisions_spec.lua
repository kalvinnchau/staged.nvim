local helpers = require('tests.helpers')

describe('revision-aware comment core', function()
  local state = require('staged.core.state')
  local comments = require('staged.core.comments')
  local position = require('staged.core.position')
  local events = require('staged.core.events')

  local buffers
  local session
  local test_tabpage

  before_each(function()
    buffers = {}
    test_tabpage = vim.api.nvim_get_current_tabpage()
    local buf = helpers.create_test_buffer({ 'work one', 'work two', 'work three' })
    table.insert(buffers, buf)
    session = state.create_session(test_tabpage)
  end)

  after_each(function()
    state.destroy_session(test_tabpage)
    for _, buf in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
  end)

  ---@param lines string[]
  ---@return integer
  local function make_buffer(lines)
    local buf = helpers.create_test_buffer(lines)
    table.insert(buffers, buf)
    return buf
  end

  it('keeps the bare path key for working-tree files', function()
    local path = '/test/working.lua'
    local buf = make_buffer({ 'a', 'b' })
    state.set_current_file(session, path, buf)

    assert.equals(path, state.file_key(path))
    assert.equals(path, state.file_key(path, { modified_revision = 'WORKING' }))
    assert.equals(path, state.file_key(path, { modified_revision = nil }))
    assert.equals(path, session.current_file)
    local file_state = state.get_current_file_state(session)
    assert.equals(path, file_state.file_path)
    assert.equals('WORKING', file_state.modified_revision)
    assert.is_nil(file_state.original_revision)
  end)

  it('builds distinct internal keys for staged and commit revisions', function()
    local path = '/test/feature.lua'
    assert.equals(path .. '\0:0', state.file_key(path, { modified_revision = ':0' }))
    assert.equals(
      path .. '\0abc123',
      state.file_key(path, { modified_revision = 'abc123', original_revision = 'def456' })
    )
    -- Identity is path + modified revision only; base revision is irrelevant
    assert.equals(
      state.file_key(path, { modified_revision = ':0' }),
      state.file_key(path, { modified_revision = ':0', original_revision = 'HEAD' })
    )
    assert.not_equals(
      state.file_key(path, { modified_revision = ':0' }),
      state.file_key(path, { modified_revision = 'abc123' })
    )
    -- WORKING is the bare path regardless of base revision
    assert.equals(
      path,
      state.file_key(path, { modified_revision = 'WORKING', original_revision = 'HEAD' })
    )
    assert.equals(path, state.file_key(path, { modified_revision = '' }))
    -- NUL delimiter cannot collide with real '#' filenames
    assert.not_equals(state.file_key('/a#b.lua', { modified_revision = ':0' }), '/a#b.lua#:0')
  end)

  it('separates comment state per revision of the same file', function()
    local path = '/test/feature.lua'
    local working_buf = make_buffer({ 'working line' })
    local staged_buf = make_buffer({ 'staged line', 'extra' })

    state.set_current_file(session, path, working_buf)
    comments.add(1, 1, 'on working tree', session)

    state.set_current_file(session, path, staged_buf, { modified_revision = ':0' })
    comments.add(1, 2, 'on staged index', session)

    -- Comments never migrate across revisions
    local working_state = state.get_file_state(session, state.file_key(path))
    local staged_state =
      state.get_file_state(session, state.file_key(path, { modified_revision = ':0' }))
    assert.equals(1, vim.tbl_count(working_state.comments))
    assert.equals(1, vim.tbl_count(staged_state.comments))
    assert.equals(':0', staged_state.modified_revision)

    for _, comment in pairs(staged_state.comments) do
      assert.equals('on staged index', comment.text)
      -- No cross-revision comment leakage
      assert.is_nil(working_state.comments[comment.id])
      assert.equals(':0', comment.modified_revision)
    end

    -- Switching back restores the working-tree identity and its comments
    state.set_current_file(session, path, working_buf)
    assert.equals('on working tree', comments.get_sorted(session)[1].text)
    assert.equals(working_buf, state.get_current_file_state(session).bufnr)
  end)

  it('preserves revision metadata on comments, events, and undo history', function()
    local path = '/test/revision_meta.lua'
    local buf = make_buffer({ 'l1', 'l2', 'l3' })
    state.set_current_file(session, path, buf, {
      modified_revision = 'feedc0de',
      original_revision = 'beefface',
    })

    local seen = {}
    vim.api.nvim_create_autocmd('User', {
      pattern = 'StagedCommentAdded',
      once = true,
      callback = function(args)
        seen.data = args.data
      end,
    })

    local comment = comments.add(2, 3, 'note', session)
    assert.equals('feedc0de', comment.modified_revision)
    assert.equals('beefface', comment.original_revision)
    assert.equals(path, comment.file_path)

    assert.equals('feedc0de', seen.data.modified_revision)
    assert.equals(path, seen.data.file_path)
    assert.equals('feedc0de', seen.data.comment.modified_revision)

    assert.is_true(require('staged').undo())
    assert.is_true(require('staged').redo())
    local restored = comments.get_sorted(session)[1]
    assert.equals('note', restored.text)
    assert.equals('feedc0de', restored.modified_revision)
    assert.equals('beefface', restored.original_revision)
  end)

  it('keeps history entries scoped to their file identity', function()
    local path = '/test/hist_scope.lua'
    local working_buf = make_buffer({ 'w1', 'w2' })
    local staged_buf = make_buffer({ 's1', 's2', 's3' })

    state.set_current_file(session, path, working_buf)
    local working_comment = comments.add(1, 1, 'working', session)

    state.set_current_file(session, path, staged_buf, { modified_revision = ':0' })
    local staged_comment = comments.add(1, 1, 'staged', session)

    -- Undo while on the staged identity only touches the staged file state
    assert.is_true(require('staged').undo())
    local staged_state =
      state.get_file_state(session, state.file_key(path, { modified_revision = ':0' }))
    assert.is_nil(staged_state.comments[staged_comment.id])

    local working_state = state.get_file_state(session, state.file_key(path))
    assert.is_not_nil(working_state.comments[working_comment.id])

    assert.is_true(require('staged').redo())
    assert.is_not_nil(staged_state.comments[staged_comment.id])
  end)

  it('base revision changes keep the same working-tree identity', function()
    local path = '/test/basechange.lua'
    local buf = make_buffer({ 'b1', 'b2' })

    state.set_current_file(session, path, buf, { original_revision = 'oldbase' })
    comments.add(1, 1, 'survives rebase', session)

    -- Re-activating with a different base revision stays one identity
    state.set_current_file(session, path, buf, { original_revision = 'newbase' })
    assert.equals(path, session.current_file)
    assert.equals(1, comments.count(session))
    assert.equals('survives rebase', comments.get_sorted(session)[1].text)
    -- Working-tree state refreshes its base metadata in place
    assert.equals('newbase', state.get_current_file_state(session).original_revision)
  end)

  it('keeps comments and exportable code when revision buffers are wiped', function()
    local path = '/test/virtual.lua'
    local virtual_buf = make_buffer({ 'virtual line one', 'virtual line two' })
    state.set_current_file(session, path, virtual_buf, { modified_revision = 'c0ffee' })
    local comment = comments.add(1, 2, 'on virtual buffer', session)

    -- Simulate the plugin's BufWipeout capture: positions and
    -- snippets are folded into the comment before the extmark disappears
    state.capture_buffer(session, virtual_buf)
    vim.api.nvim_buf_delete(virtual_buf, { force = true })

    local staged_state =
      state.get_file_state(session, state.file_key(path, { modified_revision = 'c0ffee' }))
    local kept = {}
    for _, c in pairs(staged_state.comments) do
      table.insert(kept, c)
    end
    assert.equals(1, #kept)
    assert.equals('on virtual buffer', kept[1].text)
    assert.equals('c0ffee', kept[1].modified_revision)
    -- Live position captured before the wipe; snippet survives for export
    assert.equals(1, kept[1].start_line)
    assert.equals(2, kept[1].end_line)
    assert.equals('virtual line one\nvirtual line two', kept[1].code)

    -- Export can still read the captured code without the buffer
    local formatter = require('staged.export.formatter')
    local decoded =
      vim.json.decode(require('staged.export.formatter').format(session, { format = 'json' }))
    assert.equals('c0ffee', decoded.comments[1].modified_revision)
    assert.equals('virtual line one\nvirtual line two', decoded.comments[1].code)
  end)

  it('captures dormant history anchor positions before a buffer disappears', function()
    local path = '/test/anchor_wipe.lua'
    local buf = make_buffer({ 'a1', 'a2', 'a3', 'a4' })
    state.set_current_file(session, path, buf)

    local comment = comments.add(2, 3, 'anchored', session)
    assert.is_true(require('staged').undo())
    assert.equals(0, comments.count(session))

    -- Shift the buffer while the comment is dormant: the live history
    -- extmark moves to 3-4, stale saved line numbers still say 2-3
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { 'inserted' })

    -- Simulate the plugin's capture hook running on BufWipeout: the anchor
    -- fold must read the live extmark positions, not the stale lines
    local lines_before = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    state.capture_buffer(session, buf)
    vim.api.nvim_buf_delete(buf, { force = true })

    -- Recreate the buffer matching the shifted content, then redo
    local new_buf = make_buffer(lines_before)
    state.set_current_file(session, path, new_buf)
    assert.is_true(require('staged').redo())
    local restored = comments.get_sorted(session)[1]
    assert.equals('anchored', restored.text)
    assert.same(
      { 3, 4 },
      { position.get_current_lines(session, state.get_current_file_state(session), restored) }
    )
  end)

  it('exports schema 2 records with revision and side metadata', function()
    local formatter = require('staged.export.formatter')
    local path = '/test/export_meta.lua'
    local buf = make_buffer({ 'e1', 'e2' })
    state.set_current_file(session, path, buf, {
      modified_revision = ':0',
      original_revision = 'base456',
    })
    comments.add(1, 1, 'staged note', session)

    local decoded =
      vim.json.decode(require('staged.export.formatter').format(session, { format = 'json' }))
    assert.equals(2, decoded.schema_version)
    local record = decoded.comments[1]
    assert.equals(':0', record.modified_revision)
    assert.equals('base456', record.original_revision)
    assert.equals('modified', record.side)
  end)

  it('tracks positions in the right buffer after revision switches', function()
    local path = '/test/positions.lua'
    local working_buf = make_buffer({ 'w1', 'w2', 'w3' })
    local staged_buf = make_buffer({ 's1', 's2', 's3' })

    state.set_current_file(session, path, working_buf)
    comments.add(2, 2, 'working note', session)

    state.set_current_file(session, path, staged_buf, { modified_revision = ':0' })
    comments.add(3, 3, 'staged note', session)

    state.set_current_file(session, path, working_buf)
    local file_state = state.get_current_file_state(session)
    assert.equals(working_buf, file_state.bufnr)
    local comment = comments.get_sorted(session)[1]
    assert.same({ 2, 2 }, { position.get_current_lines(session, file_state, comment) })
  end)

  it('emits comment events with actual paths even for keyed files', function()
    local path = '/test/event_path.lua'
    local buf = make_buffer({ 'p1' })
    state.set_current_file(session, path, buf, { modified_revision = ':0' })

    local seen = {}
    vim.api.nvim_create_autocmd('User', {
      pattern = 'StagedCommentsChanged',
      once = true,
      callback = function(args)
        seen.data = args.data
      end,
    })

    comments.add(1, 1, 'path check', session)
    assert.equals(path, seen.data.file_path)
    assert.equals(':0', seen.data.modified_revision)
  end)
  it('captures edited snippets and shifted positions through the real unload hook', function()
    local buf = make_buffer({ 'before', 'old code' })
    state.set_current_file(session, '/test/unload.lua', buf, { modified_revision = ':0' })
    local comment = comments.add(2, 2, 'note', session)
    vim.api.nvim_buf_set_lines(buf, 1, 2, false, { 'new code' })
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { 'inserted' })
    vim.api.nvim_buf_delete(buf, { force = true })
    local record = vim.json.decode(
      require('staged.export.formatter').format(session, { format = 'json' })
    ).comments[1]
    assert.equals(3, record.start_line)
    assert.equals('new code', record.code)
    assert.is_nil(comment.extmark_id)
  end)
  for _, dormant in ipairs({ false, true }) do
    it(
      'rearms ' .. (dormant and 'dormant' or 'live') .. ' anchors when the same buffer reloads',
      function()
        local path = vim.fn.getcwd() .. '/.review/reload-' .. vim.fn.getpid() .. '.txt'
        vim.fn.mkdir(vim.fs.dirname(path), 'p')
        vim.fn.writefile({ 'first', 'second' }, path)
        local buf = vim.fn.bufadd(path)
        vim.fn.bufload(buf)
        table.insert(buffers, buf)
        state.set_current_file(session, path, buf)
        local comment = comments.add(2, 2, 'reload', session)
        if dormant then
          comments.delete(comment.id, session)
        end
        vim.api.nvim_buf_delete(buf, { unload = true, force = true })
        assert.is_true(vim.api.nvim_buf_is_valid(buf))
        vim.fn.bufload(buf)
        state.set_current_file(session, path, buf)
        vim.api.nvim_buf_set_lines(buf, 0, 0, false, { 'inserted' })
        if dormant then
          require('staged').undo()
          comment = state.get_current_file_state(session).comments[comment.id]
        end
        local line = require('staged.core.position').get_current_lines(
          session,
          state.get_current_file_state(session),
          comment
        )
        vim.fn.delete(path)
        assert.equals(3, line)
      end
    )
  end
end)
