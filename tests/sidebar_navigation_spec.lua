-- Focused tests: sidebar panel placement, revision-aware display/navigation,
-- and close lifecycle. Owns lua/staged/ui/sidebar.lua behavior contracts.
local state = require('staged.core.state')
local config = require('staged.config')
local comments = require('staged.core.comments')
local helpers = require('tests.helpers')
local sidebar = require('staged.ui.sidebar')

describe('sidebar placement, revision display and navigation', function()
  local tabpage
  local session
  local tracked_windows
  local tracked_buffers
  local original_current_win
  local original_codediff_module
  local codediff_stub

  local function make_buffer(lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    table.insert(tracked_buffers, buf)
    return buf
  end

  local function make_window(buf, split, size)
    local win = vim.api.nvim_open_win(
      buf,
      false,
      { split = split, win = -1, [size] = size == 'width' and 30 or 6 }
    )
    table.insert(tracked_windows, win)
    return win
  end

  local function install_codediff_stub(overrides)
    codediff_stub = vim.tbl_extend('force', {
      get_codediff_session = function()
        return nil
      end,
      get_panel_view = function()
        return nil
      end,
      jump_to_comment = function()
        return false
      end,
      is_in_codediff = function()
        return false
      end,
    }, overrides or {})
    package.loaded['staged.integration.codediff'] = codediff_stub
  end

  -- The staged-keymaps autocmd runs while windows are created; without a real
  -- codediff runtime the integration module must stay stubbed for it too.
  package.loaded['staged.integration.codediff'] = codediff_stub

  local function sidebar_row_for(text)
    local lines = vim.api.nvim_buf_get_lines(session.sidebar_bufnr, 0, -1, false)
    for row, line in ipairs(lines) do
      if line:find(text, 1, true) then
        return row
      end
    end
    return nil
  end

  local function focus_sidebar_row(text)
    vim.api.nvim_set_current_win(session.sidebar_winid)
    local row = sidebar_row_for(text)
    assert.is_not_nil(row, 'sidebar should contain: ' .. text)
    vim.api.nvim_win_set_cursor(session.sidebar_winid, { row, 0 })
    return row
  end

  before_each(function()
    tabpage = vim.api.nvim_get_current_tabpage()
    original_current_win = vim.api.nvim_get_current_win()
    tracked_windows = {}
    tracked_buffers = {}
    original_codediff_module = package.loaded['staged.integration.codediff']
    install_codediff_stub()
    session = state.create_session(tabpage)
  end)

  after_each(function()
    state.destroy_session(tabpage)
    for _, win in ipairs(tracked_windows) do
      if vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    for _, buf in ipairs(tracked_buffers) do
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
    package.loaded['staged.integration.codediff'] = original_codediff_module
    if original_codediff_module == nil then
      package.loaded['staged.integration.codediff'] = nil
    end
    _G.sidebar_test_fold = nil
    vim.api.nvim_set_current_win(original_current_win)
  end)

  describe('panel placement', function()
    it('nests below a visible left panel and keeps the panel width', function()
      local panel_buf = make_buffer({ 'explorer' })
      local panel_win =
        vim.api.nvim_open_win(panel_buf, false, { split = 'left', win = -1, width = 30 })
      table.insert(tracked_windows, panel_win)
      install_codediff_stub({
        get_panel_view = function(requested)
          if requested == tabpage then
            return { winid = panel_win }
          end
        end,
      })

      local buf = make_buffer(helpers.default_lines)
      state.set_current_file(session, '/repo/a.lua', buf)
      comments.add(3, 3, 'nested note', session)

      sidebar.show(session)

      assert.is_true(session.visible)
      local side_row = vim.api.nvim_win_get_position(session.sidebar_winid)[1]
      local side_col = vim.api.nvim_win_get_position(session.sidebar_winid)[2]
      local panel_row = vim.api.nvim_win_get_position(panel_win)[1]
      local panel_col = vim.api.nvim_win_get_position(panel_win)[2]

      -- Same column as the panel, in a row below it
      assert.equals(panel_col, side_col)
      assert.is_true(side_row > panel_row)
      assert.equals(
        config.options.sidebar.height,
        vim.api.nvim_win_get_height(session.sidebar_winid)
      )
      -- Nesting must not disturb the panel column width
      assert.equals(30, vim.api.nvim_win_get_width(panel_win))

      sidebar.hide(session)
    end)

    it('falls back to a side split when the panel is hidden', function()
      local panel_buf = make_buffer({ 'explorer' })
      local panel_win =
        vim.api.nvim_open_win(panel_buf, false, { split = 'left', win = -1, width = 30 })
      table.insert(tracked_windows, panel_win)
      install_codediff_stub({
        get_panel_view = function()
          return { winid = panel_win, is_hidden = true }
        end,
      })

      sidebar.show(session)

      -- A top-level side split spans the full editor height: row 0
      assert.equals(0, vim.api.nvim_win_get_position(session.sidebar_winid)[1])
      sidebar.hide(session)
    end)

    it('falls back to a side split when the panel is on the right', function()
      local panel_buf = make_buffer({ 'explorer' })
      local panel_win =
        vim.api.nvim_open_win(panel_buf, false, { split = 'right', win = -1, width = 20 })
      table.insert(tracked_windows, panel_win)
      install_codediff_stub({
        get_panel_view = function()
          return { winid = panel_win }
        end,
      })

      sidebar.show(session)

      local side_col = vim.api.nvim_win_get_position(session.sidebar_winid)[2]
      local panel_col = vim.api.nvim_win_get_position(panel_win)[2]
      assert.equals(0, vim.api.nvim_win_get_position(session.sidebar_winid)[1])
      assert.is_true(side_col < panel_col)
      sidebar.hide(session)
    end)

    it('falls back when the panel sits at the bottom', function()
      local panel_buf = make_buffer({ 'explorer' })
      local panel_win =
        vim.api.nvim_open_win(panel_buf, false, { split = 'below', win = -1, height = 6 })
      table.insert(tracked_windows, panel_win)
      install_codediff_stub({
        get_panel_view = function()
          return { winid = panel_win }
        end,
      })

      sidebar.show(session)

      -- Full-height side split next to the diff area, never inside the
      -- bottom panel's row
      local side_row = vim.api.nvim_win_get_position(session.sidebar_winid)[1]
      local panel_row = vim.api.nvim_win_get_position(panel_win)[1]
      assert.is_true(side_row < panel_row)
      sidebar.hide(session)
    end)

    it('never inherits scroll binding or statuscolumn from diff windows', function()
      local buf = make_buffer(helpers.default_lines)
      state.set_current_file(session, '/repo/a.lua', buf)
      local diff_win = make_window(buf, 'below', 'height')
      vim.wo[diff_win].scrollbind = true
      vim.wo[diff_win].cursorbind = true
      vim.wo[diff_win].statuscolumn = '%l'

      sidebar.show(session)

      local wo = vim.wo[session.sidebar_winid]
      assert.is_false(wo.scrollbind)
      assert.is_false(wo.cursorbind)
      assert.equals('', wo.statuscolumn)

      -- The diff window is untouched
      assert.is_true(vim.wo[diff_win].scrollbind)
      assert.is_true(vim.wo[diff_win].cursorbind)
      assert.equals('%l', vim.wo[diff_win].statuscolumn)

      sidebar.hide(session)
    end)
  end)

  describe('revision-aware display', function()
    it('renders real paths with revision labels, never encoded keys', function()
      local working_buf = make_buffer(helpers.default_lines)
      local index_buf = make_buffer(helpers.default_lines)
      local commit_buf = make_buffer(helpers.default_lines)

      state.set_current_file(session, '/repo/a.lua', working_buf)
      comments.add(3, 3, 'working note', session)
      state.set_current_file(session, '/repo/b.lua', index_buf, {
        modified_revision = ':0',
        original_revision = 'HEAD',
      })
      comments.add(4, 4, 'index note', session)
      state.set_current_file(session, '/repo/c.lua', commit_buf, {
        modified_revision = '0123456789abcdef',
        original_revision = 'HEAD',
      })
      comments.add(5, 5, 'commit note', session)

      sidebar.show(session)
      local lines = vim.api.nvim_buf_get_lines(session.sidebar_bufnr, 0, -1, false)

      local joined = table.concat(lines, '\n')
      assert.is_true(joined:find('/repo/a.lua:', 1, true) ~= nil)
      assert.is_true(joined:find('/repo/b.lua @:0:', 1, true) ~= nil)
      -- Long commits are abbreviated
      assert.is_true(joined:find('/repo/c.lua @01234567:', 1, true) ~= nil)
      -- The working tree gets no label
      assert.is_true(joined:find('/repo/a.lua @', 1, true) == nil)
      -- Encoded identity keys never leak into the display
      assert.is_true(joined:find('#', 1, true) == nil)

      sidebar.hide(session)
    end)
  end)

  describe('navigation', function()
    it('routes through codediff jump_to_comment with revision identity', function()
      local working_buf = make_buffer(helpers.default_lines)
      local index_buf = make_buffer(helpers.default_lines)

      state.set_current_file(session, '/repo/w.lua', working_buf)
      comments.add(3, 3, 'working note', session)
      state.set_current_file(session, '/repo/w.lua', index_buf, {
        modified_revision = ':0',
        original_revision = 'HEAD',
      })
      comments.add(4, 4, 'index note', session)

      local jumps = {}
      install_codediff_stub({
        get_codediff_session = function()
          return { git_root = '/repo' }
        end,
        jump_to_comment = function(jump_session, file_state, jump_comment)
          table.insert(jumps, { file_state = file_state, comment = jump_comment })
          return true
        end,
      })

      sidebar.show(session)

      focus_sidebar_row('index note')
      sidebar.goto_comment(session)
      focus_sidebar_row('working note')
      sidebar.goto_comment(session)

      assert.equals(2, #jumps)
      -- Each comment navigates with its own revision identity
      assert.equals(':0', jumps[1].file_state.modified_revision)
      assert.equals('WORKING', jumps[2].file_state.modified_revision)
      assert.equals('index note', jumps[1].comment.text)
      assert.equals('working note', jumps[2].comment.text)
    end)

    it('expands compact folds in the standalone fallback window', function()
      local buf = make_buffer({
        'line 1',
        'line 2',
        'line 3',
        'line 4',
        'line 5',
        'line 6',
      })
      state.set_current_file(session, '/repo/folded.lua', buf)
      comments.add(3, 3, 'folded note', session)

      local diff_win = make_window(buf, 'below', 'height')
      -- Emulate codediff compact mode: foldmethod=expr folds lines 2-3
      _G.sidebar_test_fold = function(lnum)
        if lnum >= 2 and lnum <= 3 then
          return '1'
        end
        return '0'
      end
      vim.wo[diff_win].foldmethod = 'expr'
      vim.wo[diff_win].foldexpr = 'v:lua.sidebar_test_fold(v:lnum)'
      vim.wo[diff_win].foldenable = true
      vim.wo[diff_win].foldlevel = 0

      sidebar.show(session)
      focus_sidebar_row('folded note')
      assert.equals(
        2,
        vim.api.nvim_win_call(diff_win, function()
          return vim.fn.foldclosed(3)
        end)
      )

      sidebar.goto_comment(session)

      assert.equals(diff_win, vim.api.nvim_get_current_win())
      assert.equals(3, vim.api.nvim_win_get_cursor(0)[1])
      -- The fold covering the comment was opened
      assert.equals(
        -1,
        vim.api.nvim_win_call(diff_win, function()
          return vim.fn.foldclosed(3)
        end)
      )
    end)

    it('uses codediff jump_to_comment for unopened files', function()
      local buf = make_buffer(helpers.default_lines)
      -- The buffer is never displayed in any window
      state.set_current_file(session, '/repo/unopened.lua', buf, {
        modified_revision = 'abc123',
        original_revision = 'HEAD',
      })
      local comment = comments.add(2, 2, 'far note', session)

      local jumped
      install_codediff_stub({
        get_codediff_session = function()
          return { git_root = '/repo' }
        end,
        jump_to_comment = function(jump_session, file_state, jump_comment)
          jumped = { session = jump_session, file_state = file_state, comment = jump_comment }
          return true
        end,
      })

      sidebar.show(session)
      focus_sidebar_row('far note')
      local sidebar_win = vim.api.nvim_get_current_win()
      sidebar.goto_comment(session)

      assert.is_not_nil(jumped)
      assert.equals(session, jumped.session)
      assert.same(comment, jumped.comment)
      assert.same(
        state.get_file_state(
          session,
          state.file_key('/repo/unopened.lua', {
            modified_revision = 'abc123',
            original_revision = 'HEAD',
          })
        ),
        jumped.file_state
      )
      -- Focus stays in the sidebar; the jump is asynchronous
      assert.equals(sidebar_win, vim.api.nvim_get_current_win())
    end)

    it('notifies when navigation has no target in a standalone session', function()
      local buf = make_buffer(helpers.default_lines)
      state.set_current_file(session, '/repo/unopened.lua', buf)
      comments.add(2, 2, 'lone note', session)

      local notified = false
      local original_notify = vim.notify
      vim.notify = function()
        notified = true
      end

      sidebar.show(session)
      focus_sidebar_row('lone note')
      sidebar.goto_comment(session)
      vim.notify = original_notify

      assert.is_true(notified)
    end)
  end)
end)
