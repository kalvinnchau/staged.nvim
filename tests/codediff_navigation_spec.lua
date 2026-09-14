describe('codediff integration: panel view, roots, navigation', function()
  local state = require('staged.core.state')
  local config = require('staged.config')
  local comments = require('staged.core.comments')
  local staged = require('staged')
  local original_lifecycle = package.loaded['codediff.ui.lifecycle']

  local codediff
  local lifecycle
  local codediff_session
  local tabpage
  local original_mode
  local original_bind_session_keymaps
  local original_notify
  local buffers
  local notifications
  local selections
  local delayed_step

  local function create_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines or { 'line' })
    table.insert(buffers, bufnr)
    return bufnr
  end

  local function reload_integration()
    package.loaded['codediff.ui.lifecycle'] = lifecycle
    package.loaded['staged.integration.codediff'] = nil
    codediff = require('staged.integration.codediff')
    codediff.setup_autocmds()
  end

  -- Standard explorer diff: modified side /repo/nested/a.lua with an optional
  -- panel selection. `opts.no_panel` drops the panel view entirely.
  local function setup_diff(opts)
    opts = opts or {}
    local modified_bufnr = create_buffer({ 'a', 'b', 'c', 'd', 'e' })
    codediff_session = {
      git_root = '/repo',
      stored_diff_result = {},
      panel = { name = 'explorer' },
    }
    lifecycle.get_buffers = function()
      return 1, modified_bufnr
    end
    lifecycle.get_paths = function()
      return '/repo/original.lua', { relative = 'nested/a.lua', absolute = '/repo/nested/a.lua' }
    end
    lifecycle.get_git_context = function()
      return opts.git_context or { git_root = '/repo', modified_revision = 'WORKING' }
    end
    if not opts.no_panel then
      lifecycle.get_panel_view = function(requested)
        if requested ~= tabpage then
          return
        end
        return {
          git_root = '/repo',
          current_selection = opts.selection,
          on_file_select = function(selection, command)
            table.insert(selections, { selection = selection, command = command })
            if opts.select_error then
              error(opts.select_error)
            end
            return true
          end,
        }
      end
    end
    reload_integration()
    local session = codediff.init_for_codediff(tabpage)
    return session, modified_bufnr
  end

  -- Move the staged session to another file and comment on it, like a comment
  -- made earlier while that file was shown. `selection` is the panel selection
  -- captured at that time; init only auto-captures the currently shown file.
  local function comment_on_other_file(session, selection)
    local other_buf = create_buffer({ '1', '2', '3', '4', '5' })
    state.set_current_file(
      session,
      '/repo/other/b.lua',
      other_buf,
      { modified_revision = 'WORKING' }
    )
    local file_state = state.get_current_file_state(session)
    file_state.selection = selection
    local comment = {
      id = 'c1',
      file_path = '/repo/other/b.lua',
      start_line = 3,
      end_line = 3,
      text = 'note',
    }
    file_state.comments[comment.id] = comment
    return file_state, comment, other_buf
  end

  local function stub_diff_window(bufnr)
    local win = vim.api.nvim_open_win(bufnr, false, { split = 'below', height = 8 })
    lifecycle.get_windows = function(requested)
      if requested == tabpage then
        return 1, win
      end
    end
    return win
  end

  -- A jump that cannot complete synchronously: the diff result is still
  -- pending, so codediff must open the file before we can focus the comment.
  local function start_delayed_jump(session, file_state, comment)
    codediff_session.stored_diff_result = nil
    local defer = vim.defer_fn
    vim.defer_fn = function(callback)
      delayed_step = callback
    end
    local ok, started = pcall(codediff.jump_to_comment, session, file_state, comment)
    vim.defer_fn = defer
    assert.is_true(ok, started)
    assert.is_true(started)
    assert.equals(1, #selections)
  end

  local function assert_jump_never_focused(diff_win)
    -- Make the target ready before firing the captured timer. Missing
    -- cancellation would focus it immediately, rather than merely time out.
    codediff_session.stored_diff_result = {}
    lifecycle.get_buffers = function()
      return 1, vim.api.nvim_win_get_buf(diff_win)
    end
    lifecycle.get_paths = function()
      return '/repo/original/b.lua', { relative = 'other/b.lua', absolute = '/repo/other/b.lua' }
    end
    delayed_step()
    assert.equals(1, #selections)
    assert.equals(1, vim.api.nvim_win_get_cursor(diff_win)[1])
    assert.not_equals(diff_win, vim.api.nvim_get_current_win())
  end

  before_each(function()
    original_mode = config.options.activation.mode
    original_bind_session_keymaps = staged.bind_session_keymaps
    original_notify = vim.notify
    config.options.activation.mode = 'auto'
    tabpage = vim.api.nvim_get_current_tabpage()
    buffers = {}
    notifications = {}
    selections = {}
    delayed_step = nil
    codediff_session = nil
    lifecycle = {
      get_session = function(requested_tabpage)
        if requested_tabpage == tabpage then
          return codediff_session
        end
      end,
    }
  end)

  after_each(function()
    pcall(function()
      codediff.cancel_pending(tabpage)
    end)
    pcall(vim.api.nvim_del_augroup_by_name, 'staged-codediff')
    pcall(vim.api.nvim_del_augroup_by_name, 'staged-comment-workflow')

    local sessions = vim.tbl_keys(state.get_all_sessions())
    for _, session_tabpage in ipairs(sessions) do
      state.destroy_session(session_tabpage)
    end

    for _, bufnr in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end

    config.options.activation.mode = original_mode
    staged.bind_session_keymaps = original_bind_session_keymaps
    vim.notify = original_notify
    package.loaded['codediff.ui.lifecycle'] = original_lifecycle
    package.loaded['codediff.ui.view'] = nil
    package.loaded['codediff.core.path'] = nil
    package.loaded['staged.integration.codediff'] = nil
  end)

  describe('get_panel_view', function()
    it('returns the upstream panel view through the safe accessor', function()
      local view = { bufnr = 42, dir2 = nil }
      lifecycle.get_panel_view = function(requested)
        if requested == tabpage then
          return view
        end
      end
      reload_integration()

      assert.equals(view, codediff.get_panel_view(tabpage))
      assert.is_nil(codediff.get_panel_view(987654))
    end)

    it('returns nil when the accessor is missing or errors', function()
      reload_integration()
      assert.is_nil(codediff.get_panel_view(tabpage))

      lifecycle.get_panel_view = function()
        error('boom')
      end
      reload_integration()
      assert.is_nil(codediff.get_panel_view(tabpage))
    end)
  end)

  describe('session roots', function()
    it('prefers git_root from the git-context accessor', function()
      local modified_bufnr = create_buffer()
      codediff_session = { git_root = '/stale', stored_diff_result = {} }
      lifecycle.get_git_context = function()
        return { git_root = '/repo', modified_revision = 'WORKING' }
      end
      lifecycle.get_buffers = function()
        return 1, modified_bufnr
      end
      lifecycle.get_paths = function()
        return { absolute = '/repo/original.lua' }, { absolute = '/repo/modified.lua' }
      end
      reload_integration()

      local session = codediff.init_for_codediff(tabpage)
      assert.equals('/repo', session.root)
    end)

    it('uses the panel view dir2 root for directory compares', function()
      local modified_bufnr = create_buffer()
      codediff_session = { stored_diff_result = {} }
      lifecycle.get_panel_view = function()
        return { dir2 = '/modified-root' }
      end
      lifecycle.get_buffers = function()
        return 1, modified_bufnr
      end
      lifecycle.get_paths = function()
        return '/original-root/nested/file.lua', '/modified-root/nested/file.lua'
      end
      reload_integration()

      local session = codediff.init_for_codediff(tabpage)
      assert.equals('/modified-root', session.root)
    end)

    it('recomputes the root after switching directory files', function()
      local first_buf = create_buffer()
      codediff_session = { stored_diff_result = {} }
      lifecycle.get_panel_view = function()
        return { dir2 = '/modified-root' }
      end
      lifecycle.get_buffers = function()
        return 1, first_buf
      end
      lifecycle.get_paths = function()
        return '/original-root/a.lua', '/modified-root/a.lua'
      end
      reload_integration()

      local session = codediff.init_for_codediff(tabpage)
      assert.equals('/modified-root', session.root)

      -- Switch to a file in a different subdirectory: root stays stable.
      local second_buf = create_buffer()
      lifecycle.get_buffers = function()
        return 1, second_buf
      end
      lifecycle.get_paths = function()
        return '/original-root/deep/b.lua', '/modified-root/deep/b.lua'
      end
      codediff.init_for_codediff(tabpage)

      assert.equals('/modified-root', session.root)
      assert.equals('/modified-root/deep/b.lua', state.get_current_path(session))
    end)

    it('initializes the root correctly on a placeholder session', function()
      local modified_bufnr = create_buffer()
      codediff_session = { stored_diff_result = {} }
      lifecycle.get_panel_view = function()
        return { dir2 = '/modified-root' }
      end
      lifecycle.get_buffers = function()
        return 1, modified_bufnr
      end
      lifecycle.get_paths = function()
        return '/original-root/file.lua', '/modified-root/file.lua'
      end
      reload_integration()

      local session = codediff.init_for_codediff(tabpage)
      assert.equals('/modified-root', session.root)
    end)
  end)

  describe('review identity', function()
    it('keys file state by modified revision only, ignoring the original revision', function()
      local modified_bufnr = create_buffer()
      codediff_session = { git_root = '/repo', stored_diff_result = {} }
      lifecycle.get_git_context = function()
        return { git_root = '/repo', modified_revision = 'abc123', original_revision = 'def456' }
      end
      lifecycle.get_buffers = function()
        return 1, modified_bufnr
      end
      lifecycle.get_paths = function()
        return { absolute = '/repo/original.lua' }, { absolute = '/repo/modified.lua' }
      end
      reload_integration()

      local session = codediff.init_for_codediff(tabpage)
      local file_state = state.get_current_file_state(session)

      assert.equals('abc123', file_state.modified_revision)
      assert.equals('def456', file_state.original_revision)
      assert.equals('/repo/modified.lua', file_state.file_path)
      -- Identity comes from state.file_key, not a hardcoded '#' separator.
      assert.equals(
        state.file_key('/repo/modified.lua', { modified_revision = 'abc123' }),
        session.current_file
      )
      assert.equals(file_state, state.get_file_state(session, session.current_file))

      -- The same modified revision keeps the same file state when only the
      -- original revision changes, so comments survive re-renders.
      local comment = comments.add(1, 1, 'keep me', session)
      lifecycle.get_git_context = function()
        return { git_root = '/repo', modified_revision = 'abc123', original_revision = 'other' }
      end
      codediff.init_for_codediff(tabpage)

      assert.equals(file_state, state.get_current_file_state(session))
      assert.equals(comment, file_state.comments[comment.id])
    end)

    it('keeps the bare path key for working-tree files', function()
      local modified_bufnr = create_buffer()
      codediff_session = { git_root = '/repo', stored_diff_result = {} }
      lifecycle.get_git_context = function()
        return { git_root = '/repo', modified_revision = 'WORKING', original_revision = 'HEAD' }
      end
      lifecycle.get_buffers = function()
        return 1, modified_bufnr
      end
      lifecycle.get_paths = function()
        return { absolute = '/repo/original.lua' }, { absolute = '/repo/modified.lua' }
      end
      reload_integration()

      local session = codediff.init_for_codediff(tabpage)
      local file_state = state.get_current_file_state(session)

      assert.equals('/repo/modified.lua', file_state.file_path)
      assert.equals('WORKING', file_state.modified_revision)
      assert.equals('HEAD', file_state.original_revision)
      assert.equals('/repo/modified.lua', session.current_file)
      assert.equals(file_state, state.get_file_state(session, '/repo/modified.lua'))
    end)
  end)

  describe('jump_to_comment', function()
    it('returns false for invalid input or missing comments', function()
      reload_integration()

      assert.is_false(codediff.jump_to_comment(nil, nil, nil))

      local session = state.create_session(tabpage)
      local buf = create_buffer()
      state.set_current_file(session, '/repo/a.lua', buf)
      local file_state = state.get_current_file_state(session)
      assert.is_nil(file_state.comments['missing'])
      assert.is_false(
        codediff.jump_to_comment(session, file_state, { id = 'missing', file_path = '/repo/a.lua' })
      )
    end)

    it('switches the modified buffer and focuses the comment after a delayed update', function()
      local selection = { path = 'other/b.lua', group = 'unstaged', status = 'M' }
      local session = setup_diff({ selection = selection })
      local file_state, comment, other_buf = comment_on_other_file(session, selection)
      local diff_win = stub_diff_window(other_buf)

      start_delayed_jump(session, file_state, comment)

      -- The view update lands while the jump is pending: codediff now shows
      -- the comment's file and has a completed diff result.
      codediff_session.stored_diff_result = {}
      lifecycle.get_buffers = function()
        return 1, other_buf
      end
      lifecycle.get_paths = function()
        return '/repo/original/b.lua', { relative = 'other/b.lua', absolute = '/repo/other/b.lua' }
      end
      delayed_step()
      assert.is_true(vim.wait(2000, function()
        return vim.api.nvim_get_current_win() == diff_win
          and vim.api.nvim_win_get_cursor(diff_win)[1] == 3
          and state.get_current_bufnr(session) == other_buf
      end, 10))

      codediff.cancel_pending(tabpage)
    end)

    it('focuses the modified-side comment synchronously from the sidebar', function()
      local session, modified_bufnr = setup_diff()
      local file_state = state.get_current_file_state(session)
      local comment = comments.add(2, 2, 'note', session)

      local diff_win = stub_diff_window(modified_bufnr)
      require('staged.ui.sidebar').show(session)
      vim.api.nvim_set_current_win(session.sidebar_winid)

      assert.is_true(codediff.jump_to_comment(session, file_state, comment))
      assert.equals(diff_win, vim.api.nvim_get_current_win())
      assert.equals(2, vim.api.nvim_win_get_cursor(diff_win)[1])
      -- The file is already shown, so no panel request was needed.
      assert.equals(0, #selections)
    end)

    it('a newer file selection cancels the delayed cursor jump', function()
      local selection = { path = 'other/b.lua', group = 'unstaged', status = 'M' }
      local session = setup_diff({ selection = selection })
      local file_state, comment, other_buf = comment_on_other_file(session, selection)
      local diff_win = stub_diff_window(other_buf)

      start_delayed_jump(session, file_state, comment)
      vim.api.nvim_exec_autocmds('User', {
        pattern = 'CodeDiffFileSelect',
        modeline = false,
        data = { tabpage = tabpage, path = 'other/b.lua' },
      })

      assert_jump_never_focused(diff_win)
    end)

    it('TabLeave cancels the delayed cursor jump', function()
      local selection = { path = 'other/b.lua', group = 'unstaged', status = 'M' }
      local session = setup_diff({ selection = selection })
      local file_state, comment, other_buf = comment_on_other_file(session, selection)
      local diff_win = stub_diff_window(other_buf)

      start_delayed_jump(session, file_state, comment)
      vim.api.nvim_exec_autocmds('TabLeave', { modeline = false })

      assert_jump_never_focused(diff_win)
    end)

    it('TabClosedPre cancels the delayed cursor jump', function()
      local selection = { path = 'other/b.lua', group = 'unstaged', status = 'M' }
      local session = setup_diff({ selection = selection })
      local file_state, comment, other_buf = comment_on_other_file(session, selection)
      local diff_win = stub_diff_window(other_buf)

      start_delayed_jump(session, file_state, comment)
      vim.api.nvim_exec_autocmds('TabClosedPre', { modeline = false })

      assert_jump_never_focused(diff_win)
    end)

    it('comment deletion cancels the delayed cursor jump', function()
      local selection = { path = 'other/b.lua', group = 'unstaged', status = 'M' }
      local session = setup_diff({ selection = selection })
      local file_state, comment, other_buf = comment_on_other_file(session, selection)
      local diff_win = stub_diff_window(other_buf)

      start_delayed_jump(session, file_state, comment)
      assert.is_true(comments.delete(comment.id, session))

      assert_jump_never_focused(diff_win)
    end)

    it('session destruction cancels the delayed cursor jump', function()
      local selection = { path = 'other/b.lua', group = 'unstaged', status = 'M' }
      local session = setup_diff({ selection = selection })
      local file_state, comment, other_buf = comment_on_other_file(session, selection)
      local diff_win = stub_diff_window(other_buf)

      start_delayed_jump(session, file_state, comment)
      state.destroy_session(tabpage)
      assert.is_nil(state.get_session(tabpage))

      assert_jump_never_focused(diff_win)
    end)

    it('notifies on request errors without mutating upstream state', function()
      vim.notify = function(msg, level)
        notifications[#notifications + 1] = { msg = msg, level = level }
      end
      local selection = { path = 'other/b.lua', group = 'unstaged', status = 'M' }
      local session = setup_diff({ selection = selection, select_error = 'boom' })
      -- A windowless handle passes the usability gate so the request itself
      -- is what fails.
      lifecycle.get_windows = function()
        return 1, nil
      end
      local file_state, comment = comment_on_other_file(session, selection)

      assert.is_false(codediff.jump_to_comment(session, file_state, comment))
      assert.equals(1, #notifications)
      assert.matches('could not open comment comparison', notifications[1].msg)
      assert.equals(vim.log.levels.WARN, notifications[1].level)
      -- The failed request left the upstream session untouched.
      assert.equals('/repo', codediff_session.git_root)
      assert.equals('explorer', codediff_session.panel.name)
      assert.equals(1, #selections)
    end)

    it('falls back to view.update with actual Path refs and revision metadata', function()
      local view_calls = {}
      package.loaded['codediff.ui.view'] = {
        update = function(requested_tabpage, opts, focus)
          table.insert(view_calls, { tabpage = requested_tabpage, opts = opts, focus = focus })
          return true
        end,
      }
      package.loaded['codediff.core.path'] = {
        make_ref = function(path, git_root)
          return { path = path, git_root = git_root }
        end,
      }

      local session = setup_diff({
        no_panel = true,
        git_context = {
          git_root = '/repo',
          modified_revision = 'abc123',
          original_revision = 'HEAD~1',
        },
      })
      -- A dead window handle keeps the synchronous focus from succeeding.
      lifecycle.get_windows = function()
        return 1, nil
      end
      local file_state = state.get_current_file_state(session)
      local comment = {
        id = 'c1',
        file_path = '/repo/nested/a.lua',
        start_line = 1,
        end_line = 1,
        text = 'note',
      }
      file_state.comments[comment.id] = comment

      assert.is_true(codediff.jump_to_comment(session, file_state, comment))
      assert.equals(1, #view_calls)
      local call = view_calls[1]
      assert.equals(tabpage, call.tabpage)
      assert.is_false(call.focus)
      assert.equals('/repo', call.opts.git_root)
      assert.equals('/repo/original.lua', call.opts.original.path)
      assert.equals('/repo', call.opts.original.git_root)
      assert.equals('/repo/nested/a.lua', call.opts.modified.path)
      assert.equals('/repo', call.opts.modified.git_root)
      assert.equals('abc123', call.opts.modified_revision)
      assert.equals('HEAD~1', call.opts.original_revision)
      codediff.cancel_pending(tabpage)

      -- Working-tree comments drop the modified revision pin entirely.
      local working_buf = create_buffer({ '1', '2', '3' })
      lifecycle.get_buffers = function()
        return 1, working_buf
      end
      lifecycle.get_paths = function()
        return '/repo/original2.lua', { relative = 'two.lua', absolute = '/repo/two.lua' }
      end
      lifecycle.get_git_context = function()
        return { git_root = '/repo', modified_revision = 'WORKING', original_revision = 'HEAD' }
      end
      codediff.init_for_codediff(tabpage)
      local working_state = state.get_current_file_state(session)
      assert.equals('/repo/original2.lua', working_state.original_path)
      local working_comment = {
        id = 'c2',
        file_path = '/repo/two.lua',
        start_line = 1,
        end_line = 1,
        text = 'note',
      }
      working_state.comments[working_comment.id] = working_comment

      assert.is_true(codediff.jump_to_comment(session, working_state, working_comment))
      assert.equals(2, #view_calls)
      assert.equals('/repo/original2.lua', view_calls[2].opts.original.path)
      assert.equals('/repo/two.lua', view_calls[2].opts.modified.path)
      assert.is_nil(view_calls[2].opts.modified_revision)
      codediff.cancel_pending(tabpage)
    end)

    it('replays the saved explorer selection for directory compares', function()
      local selection = { path = 'nested/a.lua', group = 'unstaged', status = 'M' }
      local session = setup_diff({ selection = selection })
      local file_state, comment = comment_on_other_file(session, selection)
      lifecycle.get_windows = function()
        return 1, nil
      end

      assert.is_true(codediff.jump_to_comment(session, file_state, comment))
      assert.equals(1, #selections)
      local passed = selections[1]
      assert.equals('nested/a.lua', passed.selection.path)
      assert.equals('unstaged', passed.selection.group)
      assert.equals('M', passed.selection.status)
      assert.is_nil(passed.selection.commit_hash)
      assert.is_true(passed.command.force)
      codediff.cancel_pending(tabpage)
    end)

    it('replays the saved history selection including its commit hash', function()
      local selection =
        { path = 'nested/a.lua', group = 'staged', status = 'A', commit_hash = 'abc123' }
      local session = setup_diff({ selection = selection })
      local file_state, comment = comment_on_other_file(session, selection)
      lifecycle.get_windows = function()
        return 1, nil
      end

      assert.is_true(codediff.jump_to_comment(session, file_state, comment))
      assert.equals(1, #selections)
      local passed = selections[1]
      assert.equals('nested/a.lua', passed.selection.path)
      assert.equals('staged', passed.selection.group)
      assert.equals('abc123', passed.selection.commit_hash)
      assert.is_true(passed.command.force)
      codediff.cancel_pending(tabpage)
    end)

    it('does not reuse the panel current selection in place of the saved one', function()
      local selection = { path = 'nested/a.lua', group = 'unstaged', status = 'M' }
      local session = setup_diff({ selection = selection })
      local file_state, comment = comment_on_other_file(session, selection)

      -- The explorer moved on to a different file and group since the comment
      -- was made; the jump must still replay the saved selection.
      local passed
      lifecycle.get_panel_view = function(requested)
        if requested ~= tabpage then
          return
        end
        return {
          git_root = '/repo',
          current_selection = { path = 'other/b.lua', group = 'staged', status = 'D' },
          on_file_select = function(saved, command)
            passed = { selection = saved, command = command }
            return true
          end,
        }
      end
      lifecycle.get_windows = function()
        return 1, nil
      end

      assert.is_true(codediff.jump_to_comment(session, file_state, comment))
      assert.is_not_nil(passed)
      assert.equals('nested/a.lua', passed.selection.path)
      assert.equals('unstaged', passed.selection.group)
      assert.equals('M', passed.selection.status)
      codediff.cancel_pending(tabpage)
    end)
  end)
end)
