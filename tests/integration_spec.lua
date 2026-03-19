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

      local signs = helpers.get_signs(test_buf, 'staged')
      assert.equals(1, #signs)
      assert.equals(3, signs[1].lnum)
    end)

    it('should clear indicators', function()
      helpers.add_comment(3, 5, 'Comment')
      inline.render(session)
      inline.clear(session)

      local signs = helpers.get_signs(test_buf, 'staged')
      assert.equals(0, #signs)
    end)

    it('should render multiple indicators', function()
      helpers.add_comment(3, 3, 'First')
      helpers.add_comment(7, 7, 'Second')
      inline.render(session)

      local signs = helpers.get_signs(test_buf, 'staged')
      assert.equals(2, #signs)
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

      local signs = helpers.get_signs(shorter_buf, 'staged')
      assert.equals(1, #signs)
      assert.equals(2, signs[1].lnum)

      vim.api.nvim_buf_delete(shorter_buf, { force = true })
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

      local buf_count_before = #vim.api.nvim_list_bufs()
      export.to_buffer()
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

    it('should update position when lines deleted above', function()
      local c = helpers.add_comment(5, 5, 'Moving comment')

      -- Delete first 2 lines
      vim.api.nvim_buf_set_lines(test_buf, 0, 2, false, {})

      local file_state = state.get_current_file_state(session)
      local start_line, _ = position.get_current_lines(session, file_state, c)
      -- Comment should have moved up by 2 lines
      assert.equals(3, start_line)
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
      local extmark_count = helpers.count_extmarks(test_buf, session.ns_id)
      assert.is_true(extmark_count > 0)

      helpers.cleanup_session()

      extmark_count = helpers.count_extmarks(test_buf, session.ns_id)
      assert.equals(0, extmark_count)

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
      local signs = helpers.get_signs(test_buf, 'staged')
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
