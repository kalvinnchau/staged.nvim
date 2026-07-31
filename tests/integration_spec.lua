local helpers = require('tests.helpers')

describe('integration', function()
  local state = require('staged.core.state')
  local comments = require('staged.core.comments')
  local inline = require('staged.ui.inline')
  local sidebar = require('staged.ui.sidebar')
  local export = require('staged.export')
  local position = require('staged.core.position')

  local test_buf
  local session

  before_each(function()
    test_buf = helpers.create_test_buffer(helpers.default_lines)
    session = helpers.create_mock_session(test_buf, '/test/example.lua')

    -- Set buffer in a window for cursor operations
    vim.api.nvim_set_current_buf(test_buf)
  end)

  after_each(function()
    helpers.cleanup_session()
    if vim.api.nvim_buf_is_valid(test_buf) then
      vim.api.nvim_buf_delete(test_buf, { force = true })
    end
  end)

  describe('inline indicators', function()
    it('should render sign indicators', function()
      helpers.add_comment(3, 5, 'Function comment')
      inline.render(session)

      local signs = helpers.get_signs(test_buf, session)
      assert.equals(1, #signs)
      assert.equals(3, signs[1].lnum)
    end)

    it('should clear indicators', function()
      helpers.add_comment(3, 5, 'Comment')
      inline.render(session)
      inline.clear(session)

      local signs = helpers.get_signs(test_buf, session)
      assert.equals(0, #signs)
    end)

    it('should render multiple indicators', function()
      helpers.add_comment(3, 3, 'First')
      helpers.add_comment(7, 7, 'Second')
      inline.render(session)

      local signs = helpers.get_signs(test_buf, session)
      assert.equals(2, #signs)
    end)

    it('should aggregate virtual text comments on the same line', function()
      local config = require('staged.config')
      local original_style = config.options.inline.style
      config.options.inline.style = 'virtual_text'

      helpers.add_comment(3, 3, 'First')
      helpers.add_comment(3, 5, 'Second')
      inline.render(session)

      local marks =
        vim.api.nvim_buf_get_extmarks(test_buf, session.indicator_ns_id, 0, -1, { details = true })
      assert.equals(1, #marks)
      assert.equals('[2 comment(s)]', marks[1][4].virt_text[1][1])

      config.options.inline.style = original_style
    end)

    it('should clamp indicators when the file buffer changes', function()
      helpers.add_comment(10, 10, 'Trailing comment')

      local shorter_buf = helpers.create_test_buffer({
        'line 1',
        'line 2',
      })

      state.set_current_file(session, '/test/example.lua', shorter_buf)

      assert.has_no.errors(function()
        inline.render(session)
      end)

      local signs = helpers.get_signs(shorter_buf, session)
      assert.equals(1, #signs)
      assert.equals(2, signs[1].lnum)

      vim.api.nvim_buf_delete(shorter_buf, { force = true })
    end)

    it('should clear indicators from every file', function()
      helpers.add_comment(3, 3, 'First file')
      inline.render(session)

      local second_buf = helpers.create_test_buffer(helpers.default_lines)
      state.set_current_file(session, '/test/second.lua', second_buf)
      helpers.add_comment(4, 4, 'Second file')
      inline.render(session)
      inline.render(session, '/test/example.lua')

      assert.equals(1, helpers.count_extmarks(test_buf, session.indicator_ns_id))
      assert.equals(1, helpers.count_extmarks(second_buf, session.indicator_ns_id))

      require('staged').clear_all()

      assert.equals(0, helpers.count_extmarks(test_buf, session.indicator_ns_id))
      assert.equals(0, helpers.count_extmarks(second_buf, session.indicator_ns_id))

      state.set_current_file(session, '/test/example.lua', test_buf)
      vim.api.nvim_buf_delete(second_buf, { force = true })
    end)

    it('should refresh line highlights after an edit inside a comment range', function()
      local config = require('staged.config')
      local original_style = config.options.inline.style
      config.options.inline.style = 'line_highlight'

      helpers.add_comment(3, 5, 'Range comment')
      inline.render(session)
      vim.api.nvim_buf_set_text(test_buf, 3, 0, 3, 0, { '-- inserted', '' })
      vim.api.nvim_exec_autocmds('TextChanged', { buffer = test_buf, modeline = false })

      assert.is_true(vim.wait(500, function()
        return helpers.count_extmarks(test_buf, session.indicator_ns_id) == 4
      end))

      config.options.inline.style = original_style
    end)

    it('should reaggregate indicators when comment positions collapse', function()
      local config = require('staged.config')
      local original_style = config.options.inline.style
      config.options.inline.style = 'virtual_text'

      helpers.add_comment(3, 3, 'First')
      helpers.add_comment(4, 4, 'Second')
      inline.render(session)
      vim.api.nvim_buf_set_lines(test_buf, 2, 3, false, {})
      vim.api.nvim_exec_autocmds('TextChanged', { buffer = test_buf, modeline = false })

      assert.is_true(vim.wait(500, function()
        local marks = vim.api.nvim_buf_get_extmarks(
          test_buf,
          session.indicator_ns_id,
          0,
          -1,
          { details = true }
        )
        return #marks == 1 and marks[1][4].virt_text[1][1] == '[2 comment(s)]'
      end))

      config.options.inline.style = original_style
    end)
  end)

  describe('sidebar', function()
    it('should show and hide', function()
      sidebar.show(session)
      assert.is_true(session.visible)
      assert.is_not_nil(session.sidebar_winid)

      sidebar.hide(session)
      assert.is_false(session.visible)
    end)

    it('should toggle visibility', function()
      assert.is_false(session.visible)

      sidebar.toggle(session)
      assert.is_true(session.visible)

      sidebar.toggle(session)
      assert.is_false(session.visible)
    end)

    it('should recover after its window is closed externally', function()
      sidebar.show(session)
      vim.api.nvim_win_close(session.sidebar_winid, true)

      assert.is_true(vim.wait(500, function()
        return not session.visible and session.sidebar_bufnr == nil
      end))

      sidebar.show(session)
      assert.is_true(vim.api.nvim_win_is_valid(session.sidebar_winid))
      sidebar.hide(session)
    end)

    it('should render comments', function()
      helpers.add_comment(3, 5, 'Test comment')
      sidebar.show(session)
      sidebar.render(session)

      assert.is_not_nil(session.sidebar_bufnr)
      local lines = helpers.get_buffer_lines(session.sidebar_bufnr)
      -- Should contain comment count and comment text
      assert.is_true(#lines > 0)

      sidebar.hide(session)
    end)

    it('should auto-show on first comment when configured', function()
      local config = require('staged.config')
      local original = config.options.sidebar.auto_show
      config.options.sidebar.auto_show = true

      helpers.add_comment(3, 3, 'First comment')
      sidebar.maybe_auto_show(session)

      assert.is_true(session.visible)

      sidebar.hide(session)
      config.options.sidebar.auto_show = original
    end)

    it('should ignore delayed edits after the session closes', function()
      local comment = helpers.add_comment(3, 3, 'original')
      sidebar.show(session)
      local lines = helpers.get_buffer_lines(session.sidebar_bufnr)
      local comment_line
      for line, text in ipairs(lines) do
        if text:find('original', 1, true) then
          comment_line = line
          break
        end
      end
      vim.api.nvim_set_current_win(session.sidebar_winid)
      vim.api.nvim_win_set_cursor(0, { comment_line, 0 })

      local input = require('staged.ui.input')
      local original_open = input.open
      local submit
      input.open = function(_, callback)
        submit = callback
      end
      sidebar.edit_comment(session)
      state.destroy_session(session.tabpage)
      submit('late edit')
      input.open = original_open

      assert.equals('original', comment.text)
    end)

    it('should resolve the current line when jumping from stale sidebar content', function()
      helpers.add_comment(3, 3, 'Moving comment')
      sidebar.show(session)

      local sidebar_lines = helpers.get_buffer_lines(session.sidebar_bufnr)
      local comment_line
      for line, text in ipairs(sidebar_lines) do
        if text:find('Moving comment', 1, true) then
          comment_line = line
          break
        end
      end
      assert.is_not_nil(comment_line)

      vim.api.nvim_set_current_win(session.sidebar_winid)
      vim.api.nvim_win_set_cursor(0, { comment_line, 0 })
      vim.api.nvim_buf_set_text(test_buf, 2, 0, 2, 0, { '-- inserted', '' })
      sidebar.goto_comment(session)

      assert.equals(test_buf, vim.api.nvim_get_current_buf())
      assert.equals(4, vim.api.nvim_win_get_cursor(0)[1])
      sidebar.hide(session)
    end)
  end)

  describe('export', function()
    it('should format markdown with code', function()
      helpers.add_comment(3, 5, 'Function implementation')
      local formatter = require('staged.export.formatter')
      local output = formatter.format(session, { include_code = true })

      assert.is_true(output:find('example.lua') ~= nil)
      assert.is_true(output:find('Function implementation') ~= nil)
      assert.is_true(output:find('```') ~= nil)
    end)

    it('should format markdown without code', function()
      helpers.add_comment(3, 5, 'Function implementation')
      local formatter = require('staged.export.formatter')
      local output = formatter.format(session, { include_code = false })

      assert.is_true(output:find('Function implementation') ~= nil)
      assert.is_nil(output:find('```'))
    end)

    it('should export to clipboard', function()
      helpers.add_comment(3, 3, 'Clipboard test')

      -- Capture the notify to suppress it
      local notified = false
      local original_notify = vim.notify
      vim.notify = function()
        notified = true
      end

      export.to_clipboard()

      vim.notify = original_notify

      local clipboard = helpers.get_clipboard()
      assert.is_true(clipboard:find('Clipboard test') ~= nil)
      assert.is_true(notified)
    end)

    it('should export to buffer', function()
      helpers.add_comment(3, 3, 'Buffer test')

      local session_tabpage = vim.api.nvim_get_current_tabpage()
      local buf_count_before = #vim.api.nvim_list_bufs()
      export.to_buffer()
      local export_tabpage = vim.api.nvim_get_current_tabpage()
      local buf_count_after = #vim.api.nvim_list_bufs()

      -- Should have created a new buffer
      assert.is_true(buf_count_after > buf_count_before)

      -- Clean up the export buffer
      local bufs = vim.api.nvim_list_bufs()
      for _, buf in ipairs(bufs) do
        local name = vim.api.nvim_buf_get_name(buf)
        if name:find('Staged Comments Export') then
          vim.api.nvim_buf_delete(buf, { force = true })
          break
        end
      end

      vim.api.nvim_set_current_tabpage(session_tabpage)
      if vim.api.nvim_tabpage_is_valid(export_tabpage) then
        vim.api.nvim_set_current_tabpage(export_tabpage)
        vim.cmd('tabclose!')
        vim.api.nvim_set_current_tabpage(session_tabpage)
      end
    end)
  end)

  describe('position tracking', function()
    it('should track comment position via extmark', function()
      local c = helpers.add_comment(3, 5, 'Tracked comment')
      assert.is_not_nil(c.extmark_id)

      local file_state = state.get_current_file_state(session)
      local start_line, end_line = position.get_current_lines(session, file_state, c)
      assert.equals(3, start_line)
      assert.equals(5, end_line)
    end)

    it('should update position when lines inserted above', function()
      local c = helpers.add_comment(5, 5, 'Moving comment')

      -- Insert lines above the comment
      vim.api.nvim_buf_set_lines(test_buf, 0, 0, false, { '-- new line 1', '-- new line 2' })

      local file_state = state.get_current_file_state(session)
      local start_line, _ = position.get_current_lines(session, file_state, c)
      -- Comment should have moved down by 2 lines
      assert.equals(7, start_line)
    end)

    it('should stay attached when a line is inserted at its boundaries', function()
      local c = helpers.add_comment(3, 3, 'Moving comment')
      local file_state = state.get_current_file_state(session)

      vim.api.nvim_buf_set_text(test_buf, 2, 0, 2, 0, { '-- before', '' })
      local start_line, end_line = position.get_current_lines(session, file_state, c)
      assert.equals(4, start_line)
      assert.equals(4, end_line)

      local line = vim.api.nvim_buf_get_lines(test_buf, 3, 4, false)[1]
      vim.api.nvim_buf_set_text(test_buf, 3, #line, 3, #line, { '', '-- after' })
      start_line, end_line = position.get_current_lines(session, file_state, c)
      assert.equals(4, start_line)
      assert.equals(4, end_line)
    end)

    it('should update position when lines deleted above', function()
      local c = helpers.add_comment(5, 5, 'Moving comment')

      -- Delete first 2 lines
      vim.api.nvim_buf_set_lines(test_buf, 0, 2, false, {})

      local file_state = state.get_current_file_state(session)
      local start_line, _ = position.get_current_lines(session, file_state, c)
      -- Comment should have moved up by 2 lines
      assert.equals(3, start_line)
    end)

    it('should migrate tracking when a file gets a replacement buffer', function()
      local c = helpers.add_comment(5, 5, 'Moving comment')
      local replacement = helpers.create_test_buffer(helpers.default_lines)

      state.set_current_file(session, '/test/example.lua', replacement)
      vim.api.nvim_buf_set_lines(replacement, 0, 0, false, { '-- new line' })

      local file_state = state.get_current_file_state(session)
      local start_line = position.get_current_lines(session, file_state, c)
      assert.equals(6, start_line)
      assert.equals(0, helpers.count_extmarks(test_buf, session.ns_id))
      assert.equals(1, helpers.count_extmarks(replacement, session.ns_id))

      vim.api.nvim_buf_delete(replacement, { force = true })
    end)
  end)

  describe('navigation', function()
    it('should jump to next comment', function()
      helpers.add_comment(3, 3, 'First')
      helpers.add_comment(7, 7, 'Second')

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      require('staged').goto_next_comment()

      local cursor = vim.api.nvim_win_get_cursor(0)
      assert.equals(3, cursor[1])
    end)

    it('should clamp navigation when the file buffer changes', function()
      helpers.add_comment(10, 10, 'Trailing comment')

      local shorter_buf = helpers.create_test_buffer({
        'line 1',
        'line 2',
      })

      state.set_current_file(session, '/test/example.lua', shorter_buf)
      vim.api.nvim_set_current_buf(shorter_buf)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      assert.has_no.errors(function()
        require('staged').goto_next_comment()
      end)

      local cursor = vim.api.nvim_win_get_cursor(0)
      assert.equals(2, cursor[1])

      vim.api.nvim_buf_delete(shorter_buf, { force = true })
    end)

    it('should jump to previous comment', function()
      helpers.add_comment(3, 3, 'First')
      helpers.add_comment(7, 7, 'Second')

      vim.api.nvim_win_set_cursor(0, { 10, 0 })
      require('staged').goto_prev_comment()

      local cursor = vim.api.nvim_win_get_cursor(0)
      assert.equals(7, cursor[1])
    end)

    it('should wrap to first comment', function()
      helpers.add_comment(3, 3, 'First')
      helpers.add_comment(7, 7, 'Second')

      vim.api.nvim_win_set_cursor(0, { 10, 0 })
      require('staged').goto_next_comment()

      local cursor = vim.api.nvim_win_get_cursor(0)
      assert.equals(3, cursor[1])
    end)

    it('should wrap to last comment', function()
      helpers.add_comment(3, 3, 'First')
      helpers.add_comment(7, 7, 'Second')

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      require('staged').goto_prev_comment()

      local cursor = vim.api.nvim_win_get_cursor(0)
      assert.equals(7, cursor[1])
    end)
  end)

  describe('session lifecycle', function()
    it('should clean up extmarks on destroy', function()
      helpers.add_comment(3, 3, 'Comment')
      inline.render(session)
      local extmark_count = helpers.count_extmarks(test_buf, session.ns_id)
      local indicator_count = helpers.count_extmarks(test_buf, session.indicator_ns_id)
      assert.is_true(extmark_count > 0)
      assert.is_true(indicator_count > 0)

      helpers.cleanup_session()

      extmark_count = helpers.count_extmarks(test_buf, session.ns_id)
      indicator_count = helpers.count_extmarks(test_buf, session.indicator_ns_id)
      assert.equals(0, extmark_count)
      assert.equals(0, indicator_count)

      -- Recreate session for after_each cleanup
      session = helpers.create_mock_session(test_buf, '/test/example.lua')
    end)

    it('should clean up sidebar on destroy', function()
      sidebar.show(session)
      local sidebar_buf = session.sidebar_bufnr
      assert.is_true(vim.api.nvim_buf_is_valid(sidebar_buf))

      helpers.cleanup_session()

      assert.is_false(vim.api.nvim_buf_is_valid(sidebar_buf))

      -- Recreate session for after_each cleanup
      session = helpers.create_mock_session(test_buf, '/test/example.lua')
    end)

    it('should restore an existing buffer-local keymap on destroy', function()
      local original = function() end
      vim.keymap.set('n', ']m', original, {
        buffer = test_buf,
        desc = 'Original mapping',
        silent = true,
      })

      require('staged').bind_session_keymaps(session.tabpage)
      local staged_mapping = vim.api.nvim_buf_call(test_buf, function()
        return vim.fn.maparg(']m', 'n', false, true)
      end)
      assert.equals('Next staged comment', staged_mapping.desc)

      helpers.cleanup_session()
      local restored = vim.api.nvim_buf_call(test_buf, function()
        return vim.fn.maparg(']m', 'n', false, true)
      end)
      assert.equals(original, restored.callback)
      assert.equals('Original mapping', restored.desc)
      assert.equals(1, restored.silent)

      session = helpers.create_mock_session(test_buf, '/test/example.lua')
    end)

    it('should preserve a keymap replaced while the session is active', function()
      require('staged').bind_session_keymaps(session.tabpage)
      local replacement = function() end
      vim.keymap.set('n', ']m', replacement, {
        buffer = test_buf,
        desc = 'Replacement mapping',
      })

      helpers.cleanup_session()
      local mapping = vim.api.nvim_buf_call(test_buf, function()
        return vim.fn.maparg(']m', 'n', false, true)
      end)
      assert.equals(replacement, mapping.callback)
      assert.equals('Replacement mapping', mapping.desc)

      session = helpers.create_mock_session(test_buf, '/test/example.lua')
    end)

    it('should not let new history mappings override customized legacy actions', function()
      local config = require('staged.config')
      local original_edit = config.options.keymaps.edit
      local original_delete = config.options.keymaps.delete
      config.options.keymaps.edit = '<Char-117>'
      config.options.keymaps.delete = 'r'

      require('staged').bind_session_keymaps(session.tabpage)

      local edit = vim.api.nvim_buf_call(test_buf, function()
        return vim.fn.maparg('<leader>cu', 'n', false, true)
      end)
      local delete = vim.api.nvim_buf_call(test_buf, function()
        return vim.fn.maparg('<leader>cr', 'n', false, true)
      end)
      config.options.keymaps.edit = original_edit
      config.options.keymaps.delete = original_delete

      assert.equals('Edit staged comment', edit.desc)
      assert.equals('Delete staged comment', delete.desc)
    end)

    it('should not let sidebar history mappings override customized legacy actions', function()
      local config = require('staged.config')
      local original_clipboard = config.options.keymaps.export_clipboard
      local original_buffer = config.options.keymaps.export_buffer
      config.options.keymaps.export_clipboard = '<Char-117>'
      config.options.keymaps.export_buffer = 'r'

      sidebar.show(session)

      local clipboard = vim.api.nvim_buf_call(session.sidebar_bufnr, function()
        return vim.fn.maparg('<leader>cu', 'n', false, true)
      end)
      local buffer = vim.api.nvim_buf_call(session.sidebar_bufnr, function()
        return vim.fn.maparg('<leader>cr', 'n', false, true)
      end)
      config.options.keymaps.export_clipboard = original_clipboard
      config.options.keymaps.export_buffer = original_buffer

      assert.equals('Export to clipboard', clipboard.desc)
      assert.equals('Export to buffer', buffer.desc)
    end)
  end)

  describe('full workflow', function()
    it('should handle complete add-edit-delete cycle', function()
      -- Add
      local c = helpers.add_comment(3, 5, 'Initial comment')
      assert.equals(1, comments.count())
      assert.equals('Initial comment', c.text)

      -- Edit
      comments.edit(c.id, 'Updated comment')
      local file_state = state.get_current_file_state(session)
      local updated = file_state.comments[c.id]
      assert.equals('Updated comment', updated.text)

      -- Delete
      comments.delete(c.id)
      assert.equals(0, comments.count())
    end)

    it('should handle multiple comments workflow', function()
      -- Add several comments
      local c1 = helpers.add_comment(1, 1, 'Header comment')
      local c2 = helpers.add_comment(3, 5, 'Function comment')
      local c3 = helpers.add_comment(7, 9, 'Another function')

      assert.equals(3, comments.count())

      -- Render indicators
      inline.render(session)
      local signs = helpers.get_signs(test_buf, session)
      assert.equals(3, #signs)

      -- Show sidebar
      sidebar.show(session)
      sidebar.render(session)
      assert.is_true(session.visible)

      -- Export
      local formatter = require('staged.export.formatter')
      local output = formatter.format(session)
      assert.is_true(output:find('Header comment') ~= nil)
      assert.is_true(output:find('Function comment') ~= nil)
      assert.is_true(output:find('Another function') ~= nil)

      -- Clear all
      comments.clear_all()
      assert.equals(0, comments.count())

      -- Cleanup
      sidebar.hide(session)
    end)
  end)
end)
