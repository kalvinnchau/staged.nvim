describe('real codediff contract', function()
  local state = require('staged.core.state')
  local comments = require('staged.core.comments')
  local adapter = require('staged.integration.codediff')
  local lifecycle = require('codediff.ui.lifecycle')
  local sidebar = require('staged.ui.sidebar')
  local root, original_tab, tab
  local serial = 0
  local original_lines, original_columns

  local function wait_for(predicate, message)
    assert.is_true(vim.wait(5000, predicate, 10), message)
  end

  local function write(path, lines)
    vim.fn.mkdir(vim.fs.dirname(path), 'p')
    vim.fn.writefile(lines, path)
  end

  local function ready(path, revision)
    local scheduled = false
    vim.schedule(function()
      scheduled = true
    end)
    wait_for(function()
      return scheduled
    end, 'queued view updates')
    wait_for(function()
      local upstream = lifecycle.get_session(tab)
      local session = state.get_session(tab)
      local file = session and state.get_current_file_state(session)
      return upstream
        and upstream.stored_diff_result ~= nil
        and file
        and file.file_path == path
        and file.bufnr == upstream.modified_bufnr
        and (not revision or file.modified_revision == revision)
    end, 'ready: ' .. path .. ' @' .. (revision or 'WORKING'))
    return state.get_session(tab)
  end

  local function directory_diff()
    for _, side in ipairs({ 'left', 'right' }) do
      for _, path in ipairs({ 'nested/a.lua', 'other/b.lua' }) do
        write(root .. '/' .. side .. '/' .. path, { side, 'second', 'third' })
      end
    end
    vim.cmd(
      'CodeDiff dir '
        .. vim.fn.fnameescape(root .. '/left')
        .. ' '
        .. vim.fn.fnameescape(root .. '/right')
    )
    tab = vim.api.nvim_get_current_tabpage()
    return ready(root .. '/right/nested/a.lua')
  end

  local function select_file(path, status, group)
    lifecycle
      .get_panel_view(tab)
      .on_file_select({ path = path, status = status or 'M', group = group or 'unstaged' })
  end

  before_each(function()
    serial = serial + 1
    root = vim.fn.getcwd() .. '/.review/native-' .. vim.fn.getpid() .. '-' .. serial
    vim.fn.mkdir(root, 'p')
    original_tab = vim.api.nvim_get_current_tabpage()
    tab = nil
    original_lines, original_columns = vim.o.lines, vim.o.columns
    vim.o.columns = 160
    vim.o.lines = 50
  end)

  after_each(function()
    for _, page in ipairs(vim.api.nvim_list_tabpages()) do
      if page ~= original_tab then
        vim.api.nvim_set_current_tabpage(page)
        vim.cmd('tabclose!')
      end
    end
    for page in pairs(state.get_all_sessions()) do
      state.destroy_session(page)
    end
    vim.api.nvim_set_current_tabpage(original_tab)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(buf):find(root, 1, true) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    vim.fn.delete(root, 'rf')
    vim.o.lines, vim.o.columns = original_lines, original_columns
  end)

  it('preserves directory roots, revision exports, and below-panel geometry', function()
    local session = directory_diff()
    assert.equals(root .. '/right', session.root)
    comments.add(1, 1, 'first', session)
    sidebar.show(session)
    local panel = lifecycle.get_panel_view(tab)
    local panel_pos = vim.api.nvim_win_get_position(panel.winid)
    local sidebar_pos = vim.api.nvim_win_get_position(session.sidebar_winid)
    assert.equals(panel_pos[2], sidebar_pos[2])
    assert.is_true(sidebar_pos[1] > panel_pos[1])
    assert.is_false(vim.wo[session.sidebar_winid].scrollbind)
    assert.equals('', vim.wo[session.sidebar_winid].statuscolumn)

    select_file('other/b.lua')
    ready(root .. '/right/other/b.lua')
    comments.add(2, 2, 'second', session)
    local exported =
      vim.json.decode(require('staged.export.formatter').format(session, { format = 'json' }))
    assert.equals(2, exported.schema_version)
    assert.equals('nested/a.lua', exported.comments[1].path)
    assert.equals('other/b.lua', exported.comments[2].path)
  end)

  it('reopens an unopened comment file and focuses its modified-side extmark', function()
    local session = directory_diff()
    local first = state.get_current_file_state(session)
    local comment = comments.add(2, 2, 'return here', session)
    select_file('other/b.lua')
    ready(root .. '/right/other/b.lua')
    sidebar.show(session)
    vim.api.nvim_set_current_win(session.sidebar_winid)
    assert.is_true(adapter.jump_to_comment(session, first, comment))
    wait_for(function()
      local _, win = lifecycle.get_windows(tab)
      return state.get_current_file_state(session) == first
        and vim.api.nvim_get_current_win() == win
        and vim.api.nvim_win_get_cursor(win)[1] == 2
    end, 'comment jump completes')
    assert.equals('nested/a.lua', lifecycle.get_panel_view(tab).current_selection.path)
  end)

  it('preserves comments through inline toggles and rapid explorer selections', function()
    local session = directory_diff()
    local first = state.get_current_file_state(session)
    local comment = comments.add(1, 1, 'keep', session)
    require('codediff.ui.view').toggle_layout(tab)
    wait_for(function()
      return lifecycle.get_layout(tab) == 'inline'
    end, 'inline layout')
    ready(first.file_path)
    assert.equals(comment, state.get_current_file_state(session).comments[comment.id])
    select_file('other/b.lua')
    select_file('nested/a.lua')
    ready(first.file_path)
    require('codediff.ui.view').toggle_layout(tab)
    wait_for(function()
      return lifecycle.get_layout(tab) == 'side-by-side'
    end, 'side-by-side layout')
    ready(first.file_path)
    local original, modified = lifecycle.get_windows(tab)
    assert.is_true(vim.wo[original].scrollbind)
    assert.is_true(vim.wo[modified].scrollbind)
    assert.equals(comment, state.get_current_file_state(session).comments[comment.id])
  end)

  it('falls back when the explorer is hidden and tears down on tab closure', function()
    local session = directory_diff()
    comments.add(1, 1, 'cleanup', session)
    require('codediff.ui.view.actions.panes').toggle_explorer({ tabpage = tab })
    sidebar.show(session)
    assert.is_true(vim.api.nvim_win_is_valid(session.sidebar_winid))
    local file = state.get_current_file_state(session)
    local buf = file.bufnr
    local namespace = session.ns_id
    vim.cmd('tabclose!')
    wait_for(function()
      return state.get_session(tab) == nil
    end, 'session removed')
    assert.is_nil(lifecycle.get_session(tab))
    if vim.api.nvim_buf_is_valid(buf) then
      assert.equals(0, #vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, {}))
    end
  end)

  it('isolates index and working comments and handles added/deleted files', function()
    local repo = root .. '/repo'
    local clone = vim
      .system({ 'git', 'clone', '--shared', '--no-hardlinks', '--quiet', vim.fn.getcwd(), repo })
      :wait()
    assert.equals(0, clone.code, clone.stderr)
    local path = repo .. '/README.md'
    local lines = vim.fn.readfile(path)
    table.insert(lines, 1, 'index change')
    vim.fn.writefile(lines, path)
    local index = vim.system({ 'git', '-C', repo, 'add', 'README.md' }):wait()
    assert.equals(0, index.code, index.stderr)
    table.insert(lines, 1, 'working change')
    vim.fn.writefile(lines, path)
    write(repo .. '/added.lua', { 'new file' })
    assert.equals(0, vim.fn.delete(repo .. '/LICENSE'))
    local previous_tab = vim.api.nvim_get_current_tabpage()
    vim.cmd('CodeDiff --repo ' .. vim.fn.fnameescape(repo))
    wait_for(function()
      return vim.api.nvim_get_current_tabpage() ~= previous_tab
    end, 'git diff tab')
    tab = vim.api.nvim_get_current_tabpage()
    wait_for(function()
      return lifecycle.get_panel_view(tab) ~= nil
    end, 'git explorer')
    select_file('README.md', 'M', 'unstaged')
    local session = ready(path, 'WORKING')
    local working = state.get_current_file_state(session)
    local comment = comments.add(1, 1, 'working', session)
    select_file('README.md', 'M', 'staged')
    ready(path, ':0')
    local staged_file = state.get_current_file_state(session)
    assert.not_equals(working, staged_file)
    assert.is_nil(staged_file.comments[comment.id])
    local index_comment = comments.add(1, 1, 'index', session)
    select_file('added.lua', '??')
    ready(repo .. '/added.lua', 'WORKING')
    assert.is_true(adapter.jump_to_comment(session, staged_file, index_comment))
    ready(path, ':0')
    assert.equals(index_comment, state.get_current_file_state(session).comments[index_comment.id])
    select_file('LICENSE', 'D')
    wait_for(function()
      local original, modified = lifecycle.get_paths(tab)
      return original
        and original.absolute == repo .. '/LICENSE'
        and modified
        and modified.absolute == ''
    end, 'deleted file original side')
    wait_for(function()
      return state.get_current_file_state(session) == nil
    end, 'no modified side')
    select_file('README.md', 'M', 'unstaged')
    ready(path, 'WORKING')
    assert.equals(comment, state.get_current_file_state(session).comments[comment.id])
  end)
  it('refreshes opt-in badges after mutations and upstream renders without tab context', function()
    local codediff = require('codediff')
    local previous = vim.deepcopy(require('codediff.config').options)
    local badges = require('staged.integration.explorer')
    codediff.setup(
      vim.tbl_deep_extend('force', previous, { explorer = { formatters = badges.formatters() } })
    )
    local ok, err = pcall(function()
      local session = directory_diff()
      local panel = lifecycle.get_panel_view(tab)
      comments.add(1, 1, 'badge', session)
      local function has_badge()
        return table
          .concat(vim.api.nvim_buf_get_lines(panel.bufnr, 0, -1, false), '\n')
          :find('comments:1', 1, true) ~= nil
      end
      wait_for(has_badge, 'comment badge appears')
      vim.api.nvim_set_current_win(lifecycle.get_session(tab).modified_win)
      panel.tree:render()
      wait_for(has_badge, 'corrective redraw restores badge')
      require('staged').undo()
      wait_for(function()
        return not has_badge()
      end, 'undo clears badge')
    end)
    codediff.setup(previous)
    assert.is_true(ok, err)
  end)
  it('reopens a panel-less commit comparison with its original paths and revisions', function()
    local repo = root .. '/repo'
    local cloned = vim
      .system({ 'git', 'clone', '--shared', '--no-hardlinks', '--quiet', vim.fn.getcwd(), repo })
      :wait()
    assert.equals(0, cloned.code, cloned.stderr)
    local head = vim.trim(vim.system({ 'git', '-C', repo, 'rev-parse', 'HEAD' }):wait().stdout)
    local base = vim.trim(vim.system({ 'git', '-C', repo, 'rev-parse', 'HEAD^' }):wait().stdout)
    local path = require('codediff.core.path')
    local view = require('codediff.ui.view')
    local function comparison(file)
      return {
        git_root = repo,
        original = path.make_ref(file, repo),
        modified = path.make_ref(file, repo),
        original_revision = base,
        modified_revision = head,
      }
    end
    local previous_tab = vim.api.nvim_get_current_tabpage()
    view.create(comparison('README.md'))
    wait_for(function()
      return vim.api.nvim_get_current_tabpage() ~= previous_tab
    end, 'bare revision tab')
    tab = vim.api.nvim_get_current_tabpage()
    local session = ready(repo .. '/README.md', head)
    local file = state.get_current_file_state(session)
    local comment = comments.add(2, 2, 'revision comment', session)
    assert.is_nil(lifecycle.get_panel_view(tab))
    assert.is_true(view.update(tab, comparison('LICENSE'), false))
    ready(repo .. '/LICENSE', head)
    assert.is_true(adapter.jump_to_comment(session, file, comment))
    ready(repo .. '/README.md', head)
    wait_for(function()
      local _, win = lifecycle.get_windows(tab)
      return vim.api.nvim_get_current_win() == win and vim.api.nvim_win_get_cursor(win)[1] == 2
    end, 'bare revision comment focus')
    assert.equals(base, lifecycle.get_git_context(tab).original_revision)
  end)
end)
