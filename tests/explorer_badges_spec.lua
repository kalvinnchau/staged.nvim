describe('explorer comment badges', function()
  local state = require('staged.core.state')
  local comments = require('staged.core.comments')
  local badges
  local saved, sessions, panels, buffers, base_tab, config
  local module_names = {
    'codediff.ui.lifecycle',
    'codediff.config',
    'codediff.ui.explorer.formatters',
    'staged.integration.explorer',
  }

  local function buffer(lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or { 'line' })
    table.insert(buffers, buf)
    return buf
  end

  local function session(root)
    local tab = vim.api.nvim_get_current_tabpage()
    local s = state.create_session(tab)
    s.root = root
    sessions[tab] = s
    panels[tab] = { bufnr = buffer(), tree = { render = function() end } }
    return s
  end

  local function add(s, revision)
    state.set_current_file(s, s.root .. '/file.lua', buffer(), { modified_revision = revision })
    comments.add(1, 1, 'comment', s)
  end

  local function text(layout)
    local parts = {}
    for _, region in ipairs(layout.right or {}) do
      for _, segment in ipairs(region.segments) do
        table.insert(parts, segment.text)
      end
    end
    return table.concat(parts)
  end

  before_each(function()
    saved, sessions, panels, buffers = {}, {}, {}, {}
    base_tab = vim.api.nvim_get_current_tabpage()
    for _, name in ipairs(module_names) do
      saved[name] = package.loaded[name]
    end
    package.loaded['codediff.ui.lifecycle'] = {
      get_session = function()
        return nil
      end,
      get_panel_view = function(tab)
        return panels[tab]
      end,
    }
    config = { options = { explorer = { formatters = {} } } }
    package.loaded['codediff.config'] = config
    local function original()
      return { left = {}, right = { { segments = { { text = 'M' } } } } }
    end
    package.loaded['codediff.ui.explorer.formatters'] =
      { file = original, folder = original, group = original }
    package.loaded['staged.integration.explorer'] = nil
    badges = require('staged.integration.explorer')
    badges.setup()
  end)

  after_each(function()
    config.options.explorer.formatters = {}
    for tab in pairs(sessions) do
      state.destroy_session(tab)
    end
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      if tab ~= base_tab then
        vim.api.nvim_set_current_tabpage(tab)
        vim.cmd('tabclose!')
      end
    end
    for _, buf in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    vim.api.nvim_del_augroup_by_name('staged-explorer-badges')
    for _, name in ipairs(module_names) do
      package.loaded[name] = saved[name]
    end
  end)

  it('counts file, folder, and group rows by modified revision', function()
    local s = session('/repo')
    add(s, 'WORKING')
    add(s, ':0')
    add(s, 'commit-a')
    local f = badges.formatters({ tabpage = s.tabpage })
    assert.equals('M comments:1', text(f.file({ path = 'file.lua', group = 'staged' })))
    assert.equals('M comments:1', text(f.file({ path = 'file.lua', group = 'unstaged' })))
    local ctx = {
      files = { { path = 'file.lua', group = 'staged' }, { path = 'file.lua', group = 'unstaged' } },
    }
    assert.equals('M comments:2', text(f.folder(ctx)))
    assert.equals('M comments:2', text(f.group(ctx)))
    panels[s.tabpage].target_revision = 'commit-a'
    assert.equals('M comments:1', text(f.file({ path = 'file.lua', group = 'unstaged' })))
    assert.equals('M', text(f.file({ path = 'unknown.lua' })))
  end)

  it('does not mutate a custom formatter layout and forwards its errors', function()
    local s = session('/repo')
    add(s, 'WORKING')
    local layout = { right = { { segments = { { text = 'custom' } } } } }
    local f = badges.formatters({
      tabpage = s.tabpage,
      file = function()
        return layout
      end,
    })
    assert.equals('custom comments:1', text(f.file({ path = 'file.lua' })))
    assert.equals('custom', text(layout))
    f = badges.formatters({
      file = function()
        error('formatter failed')
      end,
    })
    assert.has_error(function()
      f.file({ path = 'file.lua' })
    end)
  end)

  it('omits ambiguous render counts and keeps different tabs isolated', function()
    local first = session('/one')
    add(first, 'WORKING')
    local f = badges.formatters()
    assert.equals('M', text(f.file({ path = 'file.lua' })))
    vim.api.nvim_set_current_buf(panels[first.tabpage].bufnr)
    assert.equals('M comments:1', text(f.file({ path = 'file.lua' })))
    vim.cmd('tabnew')
    local second = session('/two')
    add(second, 'WORKING')
    add(second, 'WORKING')
    vim.api.nvim_set_current_buf(panels[second.tabpage].bufnr)
    assert.equals('M comments:2', text(f.file({ path = 'file.lua' })))
    local first_formatter = badges.formatters({ tabpage = first.tabpage })
    assert.equals('M comments:1', text(first_formatter.file({ path = 'file.lua' })))
  end)

  it('coalesces changes, corrects upstream redraws, and stops after teardown', function()
    local s = session('/repo')
    add(s, 'WORKING')
    local f = badges.formatters()
    config.options.explorer.formatters = f
    local panel = panels[s.tabpage]
    local renders = 0
    panel.tree.render = function()
      renders = renders + 1
      vim.api.nvim_buf_set_lines(panel.bufnr, 0, -1, false, { text(f.file({ path = 'file.lua' })) })
    end
    local function changed()
      vim.api.nvim_exec_autocmds(
        'User',
        { pattern = 'StagedCommentsChanged', data = { tabpage = s.tabpage } }
      )
    end
    changed()
    changed()
    assert.is_true(vim.wait(500, function()
      return renders == 1
    end))
    assert.equals('M comments:1', vim.api.nvim_buf_get_lines(panel.bufnr, 0, 1, false)[1])
    panel.tree:render()
    assert.is_true(vim.wait(500, function()
      return renders == 3
    end))
    assert.equals('M comments:1', vim.api.nvim_buf_get_lines(panel.bufnr, 0, 1, false)[1])
    state.destroy_session(s.tabpage)
    changed()
    local flushed = false
    vim.schedule(function()
      flushed = true
    end)
    assert.is_true(vim.wait(500, function()
      return flushed
    end))
    assert.equals(3, renders)
  end)

  it('does not redraw when its wrappers are not installed', function()
    local s = session('/repo')
    local renders = 0
    panels[s.tabpage].tree.render = function()
      renders = renders + 1
    end
    badges.formatters()
    vim.api.nvim_exec_autocmds(
      'User',
      { pattern = 'StagedCommentsChanged', data = { tabpage = s.tabpage } }
    )
    local flushed = false
    vim.schedule(function()
      flushed = true
    end)
    assert.is_true(vim.wait(500, function()
      return flushed
    end))
    assert.equals(0, renders)
  end)
end)
