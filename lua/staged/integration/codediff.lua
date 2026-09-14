local M = {}

local state = require('staged.core.state')
local config = require('staged.config')

local wait_interval_ms = 25
local max_wait_attempts = 400
local pending = { sync = {}, navigation = {} }

-- Both kinds of work share scheduling/teardown, but tab leave cancels only
-- navigation: background file synchronization must still complete.
local function poll(tabpage, kind, check, on_timeout)
  local token = {}
  pending[kind][tabpage] = token
  local attempt = 0
  local function step()
    if pending[kind][tabpage] ~= token then
      return
    end
    if not vim.api.nvim_tabpage_is_valid(tabpage) then
      pending[kind][tabpage] = nil
      return
    end
    attempt = attempt + 1
    if check() then
      if pending[kind][tabpage] == token then
        pending[kind][tabpage] = nil
      end
      return
    end
    if attempt >= max_wait_attempts then
      pending[kind][tabpage] = nil
      if on_timeout then
        on_timeout()
      end
      return
    end
    vim.defer_fn(step, wait_interval_ms)
  end
  -- FileSelect precedes codediff's queued update; never accept its old result.
  vim.defer_fn(step, wait_interval_ms)
end

local function cancel_nav(tabpage)
  pending.navigation[tabpage] = nil
end

local function cancel_pending(tabpage)
  pending.sync[tabpage] = nil
  cancel_nav(tabpage)
end

---@return table|nil
local function get_lifecycle()
  local ok, lifecycle = pcall(require, 'codediff.ui.lifecycle')
  if not ok or type(lifecycle.get_session) ~= 'function' then
    return nil
  end
  return lifecycle
end

---@param path string
---@return string
local function normalize_path(path)
  return (vim.fs.normalize(path):gsub('\\', '/'))
end

---@param path_ref table|string|nil
---@return string|nil
local function absolute_path(path_ref)
  if type(path_ref) == 'table' then
    return path_ref.absolute
  end
  if type(path_ref) == 'string' then
    return path_ref
  end
  return nil
end

---Stable session root: git_root when present, else the modified-side directory
---root (explorer dir2 for directory compares), else the file's own directory.
---@param lifecycle table
---@param tabpage integer
---@param codediff_session table
---@param modified_path string
---@return string
local function get_session_root(lifecycle, tabpage, codediff_session, modified_path)
  local git_context = type(lifecycle.get_git_context) == 'function'
      and select(2, pcall(lifecycle.get_git_context, tabpage))
    or nil
  if
    type(git_context) == 'table'
    and type(git_context.git_root) == 'string'
    and git_context.git_root ~= ''
  then
    return git_context.git_root
  end

  if type(codediff_session.git_root) == 'string' and codediff_session.git_root ~= '' then
    return codediff_session.git_root
  end

  -- Panel views (explorer/history) carry the roots: explorer keeps dir2 for
  -- directory compares; get_panel_view is the safe read-only accessor.
  local panel_view = type(lifecycle.get_panel_view) == 'function'
      and select(2, pcall(lifecycle.get_panel_view, tabpage))
    or nil
  if type(panel_view) == 'table' then
    local dir2 = panel_view.dir2
    if type(dir2) == 'string' and dir2 ~= '' then
      return normalize_path(dir2)
    end
    if type(panel_view.git_root) == 'string' and panel_view.git_root ~= '' then
      return panel_view.git_root
    end
  end

  return vim.fs.dirname(modified_path)
end

---@param lifecycle table
---@param tabpage integer
---@param codediff_session table
---@return integer|nil modified_bufnr
---@return table|string|nil modified_ref
local function get_modified_file(lifecycle, tabpage, codediff_session)
  local modified_bufnr = codediff_session.modified_bufnr
  if type(lifecycle.get_buffers) == 'function' then
    local ok, _, bufnr = pcall(lifecycle.get_buffers, tabpage)
    if ok and bufnr then
      modified_bufnr = bufnr
    end
  end

  local modified_ref = codediff_session.modified or codediff_session.modified_path
  if type(lifecycle.get_paths) == 'function' then
    local ok, _, path_ref = pcall(lifecycle.get_paths, tabpage)
    if ok and path_ref then
      modified_ref = path_ref
    end
  end

  return modified_bufnr, modified_ref
end

---Read current revisions through the safe git-context accessor, falling back
---to legacy session fields.
---@param lifecycle table
---@param tabpage integer
---@param codediff_session table
---@return StagedReviewContext
local function get_revisions(lifecycle, tabpage, codediff_session)
  local context = type(lifecycle.get_git_context) == 'function'
      and select(2, pcall(lifecycle.get_git_context, tabpage))
    or nil
  if type(context) == 'table' then
    return {
      modified_revision = state.normalize_revision(context.modified_revision),
      original_revision = context.original_revision,
    }
  end
  return {
    modified_revision = state.normalize_revision(codediff_session.modified_revision),
    original_revision = codediff_session.original_revision,
  }
end

---@param lifecycle table
---@param tabpage integer
---@param codediff_session table
---@param selected_path string
---@return boolean
local function selected_path_matches(lifecycle, tabpage, codediff_session, selected_path)
  local _, modified_ref = get_modified_file(lifecycle, tabpage, codediff_session)

  local normalized_selected = normalize_path(selected_path)
  if type(modified_ref) == 'table' and modified_ref.relative then
    if normalize_path(modified_ref.relative) == normalized_selected then
      return true
    end
  end

  local modified_path = absolute_path(modified_ref)
  if not modified_path or modified_path == '' then
    return false
  end
  if normalize_path(modified_path) == normalized_selected then
    return true
  end

  if codediff_session.git_root and codediff_session.git_root ~= '' then
    local selected_absolute = vim.fs.joinpath(codediff_session.git_root, selected_path)
    return normalize_path(modified_path) == normalize_path(selected_absolute)
  end

  return false
end

---@param tabpage integer
---@return boolean
local function should_sync(tabpage)
  return not state.is_destroying(tabpage)
    and (config.options.activation.mode == 'auto' or state.get_session(tabpage) ~= nil)
end

---@param tabpage integer
local function sync_session(tabpage)
  if should_sync(tabpage) then
    M.init_for_codediff(tabpage)
  end
end

---Resolve an explorer row's modified revision, shared with comment badges.
function M.revision_for_group(panel, group)
  local revision = panel and panel.target_revision
  if revision and state.normalize_revision(revision) ~= 'WORKING' then
    return revision
  end
  if group == 'staged' then
    return ':0'
  end
  if group == 'unstaged' then
    return 'WORKING'
  end
  if group == 'conflicts' then
    local ok, codediff_config = pcall(require, 'codediff.config')
    local ours = ok and codediff_config.options.diff.conflict_ours_position or 'right'
    return ours == 'left' and ':3' or ':2'
  end
end

local function view_ready(lifecycle, tabpage, upstream, path, revision, allow_original)
  if not upstream or upstream.stored_diff_result == nil then
    return false
  end
  local buf, ref = get_modified_file(lifecycle, tabpage, upstream)
  if absolute_path(ref) == '' then
    if not allow_original then
      return false
    end
    if not path then
      return true
    end
    local ok, original = pcall(lifecycle.get_paths or function() end, tabpage)
    return ok
      and type(original) == 'table'
      and (original.relative == path or original.absolute == path)
  end
  return buf
    and vim.api.nvim_buf_is_valid(buf)
    and vim.api.nvim_buf_is_loaded(buf)
    and (not path or selected_path_matches(lifecycle, tabpage, upstream, path))
    and (not revision or get_revisions(lifecycle, tabpage, upstream).modified_revision == revision)
end

local function wait_for_update(tabpage, selected_path)
  if not should_sync(tabpage) then
    return
  end
  local panel = M.get_panel_view(tabpage)
  local selection = panel and panel.current_selection
  selected_path = selected_path or (selection and selection.path)
  local revision = M.revision_for_group(panel, selection and selection.group)
  poll(tabpage, 'sync', function()
    if not should_sync(tabpage) then
      return true
    end
    local lifecycle = get_lifecycle()
    local upstream = lifecycle and M.get_codediff_session(tabpage)
    if not upstream then
      return true
    end
    if view_ready(lifecycle, tabpage, upstream, selected_path, revision, true) then
      sync_session(tabpage)
      return true
    end
  end)
end

---@param args table
---@return integer|nil
local function event_tabpage(args)
  local tabpage = args.data and args.data.tabpage
  if type(tabpage) == 'number' then
    return tabpage
  end
  return nil
end

---Check if codediff.nvim is available
---@return boolean
function M.is_available()
  return get_lifecycle() ~= nil
end

---Get codediff session for a tabpage
---@param tabpage integer
---@return table|nil codediff session
function M.get_codediff_session(tabpage)
  local lifecycle = get_lifecycle()
  if not lifecycle then
    return nil
  end

  local ok, session = pcall(lifecycle.get_session, tabpage)
  return ok and session or nil
end

---Safe read-only accessor for the codediff side-panel view (explorer/history).
---Returns the upstream panel view object or nil; never mutates codediff state.
---@param tabpage integer
---@return table|nil panel_view
function M.get_panel_view(tabpage)
  local lifecycle = get_lifecycle()
  if not lifecycle or type(lifecycle.get_panel_view) ~= 'function' then
    return nil
  end

  local ok, view = pcall(lifecycle.get_panel_view, tabpage)
  if ok and type(view) == 'table' then
    return view
  end
  return nil
end

---Check if current buffer is in a codediff view
---@return boolean
function M.is_in_codediff()
  local tabpage = vim.api.nvim_get_current_tabpage()
  return M.get_codediff_session(tabpage) ~= nil
end

---Initialize or update staged session for a codediff tabpage
---@param tabpage integer
---@return StagedSession|nil
function M.init_for_codediff(tabpage)
  if state.is_destroying(tabpage) then
    return nil
  end

  local lifecycle = get_lifecycle()
  local codediff_session = lifecycle and M.get_codediff_session(tabpage) or nil
  if not codediff_session then
    return nil
  end

  local modified_bufnr, modified_ref = get_modified_file(lifecycle, tabpage, codediff_session)
  local modified_path = absolute_path(modified_ref)
  if
    not modified_bufnr
    or not vim.api.nvim_buf_is_valid(modified_bufnr)
    or not modified_path
    or modified_path == ''
    or codediff_session.stored_diff_result == nil
  then
    local session = state.get_session(tabpage)
    if session then
      state.deactivate_current_file(session)
    end
    return nil
  end

  local revisions = get_revisions(lifecycle, tabpage, codediff_session)

  local session = state.get_session(tabpage)
  if not session then
    -- Placeholder initial sessions (panel views create the diff lazily) have
    -- no root yet; the root is recomputed below from live accessors so the
    -- first real init still lands on the right root.
    session = state.create_session(tabpage)
  end
  session.root = get_session_root(lifecycle, tabpage, codediff_session, modified_path)

  state.set_current_file(session, modified_path, modified_bufnr, revisions)
  local file_state = state.get_current_file_state(session)
  file_state.git_root = codediff_session.git_root
  local paths_ok, original_ref = pcall(lifecycle.get_paths or function() end, tabpage)
  if paths_ok then
    file_state.original_path = absolute_path(original_ref)
  end
  local panel = M.get_panel_view(tabpage)
  local selection = panel and panel.current_selection
  if
    selection
    and type(selection.path) == 'string'
    and selected_path_matches(lifecycle, tabpage, codediff_session, selection.path)
  then
    file_state.selection = vim.deepcopy(selection)
  end
  require('staged.ui.inline').render(session)
  require('staged.ui.sidebar').render(session)
  require('staged').bind_session_keymaps(tabpage)

  return session
end

local function navigation_alive(session, file_state, comment)
  return state.get_session(session.tabpage) == session
    and vim.api.nvim_get_current_tabpage() == session.tabpage
    and file_state.comments[comment.id] == comment
end

local function focus_comment(session, file_state, comment, lifecycle)
  local ok, _, win = pcall(lifecycle.get_windows, session.tabpage)
  if
    not ok
    or not win
    or not vim.api.nvim_win_is_valid(win)
    or vim.api.nvim_win_get_buf(win) ~= file_state.bufnr
  then
    return false
  end
  local line = require('staged.core.position').get_current_lines(session, file_state, comment)
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_cursor(win, { line, 0 })
  vim.cmd('normal! zv')
  return true
end

---Open the original comparison through codediff, then focus its modified-side comment.
---Tokens cancel our follow-up jump, not work already submitted to codediff.
---@param session StagedSession
---@param file_state StagedFileState
---@param comment StagedComment
---@return boolean
function M.jump_to_comment(session, file_state, comment)
  if
    not session
    or not file_state
    or not comment
    or not navigation_alive(session, file_state, comment)
  then
    return false
  end
  local lifecycle = get_lifecycle()
  local upstream = lifecycle and M.get_codediff_session(session.tabpage)
  if not upstream or type(lifecycle.get_windows) ~= 'function' then
    vim.notify('staged.nvim: no usable codediff view for this comment', vim.log.levels.WARN)
    return false
  end
  cancel_pending(session.tabpage)
  if
    state.get_current_file_state(session) == file_state
    and upstream.stored_diff_result ~= nil
    and focus_comment(session, file_state, comment, lifecycle)
  then
    return true
  end

  local panel = M.get_panel_view(session.tabpage)
  local selection = file_state.selection
  local ok, result
  if panel and selection and type(panel.on_file_select) == 'function' then
    ok, result = pcall(panel.on_file_select, vim.deepcopy(selection), { force = true })
  else
    local view_ok, view = pcall(require, 'codediff.ui.view')
    local path_ok, path = pcall(require, 'codediff.core.path')
    if
      not view_ok
      or type(view.update) ~= 'function'
      or not path_ok
      or type(path.make_ref) ~= 'function'
      or not file_state.original_path
    then
      vim.notify('staged.nvim: the original comparison is unavailable', vim.log.levels.WARN)
      return false
    end
    local revision = file_state.modified_revision
    if revision == 'WORKING' then
      revision = nil
    end
    ok, result = pcall(function()
      return view.update(session.tabpage, {
        git_root = file_state.git_root,
        original = path.make_ref(file_state.original_path, file_state.git_root),
        modified = path.make_ref(file_state.file_path, file_state.git_root),
        original_revision = file_state.original_revision,
        modified_revision = revision,
      }, false)
    end)
  end
  if not ok or result == false then
    vim.notify(
      'staged.nvim: could not open comment comparison: ' .. tostring(result),
      vim.log.levels.WARN
    )
    return false
  end

  local requested_selection = panel and vim.deepcopy(panel.current_selection)
  poll(session.tabpage, 'navigation', function()
    if
      not navigation_alive(session, file_state, comment)
      or (panel and not vim.deep_equal(panel.current_selection, requested_selection))
    then
      return true
    end
    local upstream = M.get_codediff_session(session.tabpage)
    if not upstream then
      return true
    end
    if
      view_ready(
        lifecycle,
        session.tabpage,
        upstream,
        file_state.file_path,
        state.normalize_revision(file_state.modified_revision),
        false
      )
    then
      M.init_for_codediff(session.tabpage)
      if state.get_current_file_state(session) == file_state then
        focus_comment(session, file_state, comment, lifecycle)
      end
      return true
    end
  end, function()
    vim.notify('staged.nvim: timed out opening comment comparison', vim.log.levels.WARN)
  end)

  return true
end

---Cancel pending operations for a tabpage (public, used by lifecycle hooks)
---@param tabpage integer
function M.cancel_pending(tabpage)
  cancel_pending(tabpage)
end

---Setup autocmds to track codediff sessions
function M.setup_autocmds()
  local group = vim.api.nvim_create_augroup('staged-codediff', { clear = true })
  pending = { sync = {}, navigation = {} }

  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'CodeDiffOpen',
    callback = function(args)
      local tabpage = event_tabpage(args) or vim.api.nvim_get_current_tabpage()
      wait_for_update(tabpage)
    end,
  })

  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'CodeDiffFileSelect',
    callback = function(args)
      local tabpage = event_tabpage(args) or vim.api.nvim_get_current_tabpage()
      local selected_path = args.data and args.data.path or nil
      -- A newer user-driven selection cancels any pending navigation clamp.
      cancel_nav(tabpage)
      wait_for_update(tabpage, selected_path)
    end,
  })

  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'CodeDiffClose',
    callback = function(args)
      local tabpage = event_tabpage(args)
      if tabpage then
        cancel_pending(tabpage)
        state.destroy_session(tabpage)
      end
    end,
  })

  -- TabClosedPre (nvim >= 0.12): the window layout is locked here, so only
  -- cancel pending work; never touch windows. Safe post-close cleanup stays
  -- on the TabClosed fallback below.
  vim.api.nvim_create_autocmd('TabClosedPre', {
    group = group,
    callback = function()
      cancel_pending(vim.api.nvim_get_current_tabpage())
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter', 'TabEnter' }, {
    group = group,
    callback = function()
      local tabpage = vim.api.nvim_get_current_tabpage()
      sync_session(tabpage)
      if M.get_codediff_session(tabpage) and not pending.sync[tabpage] then
        wait_for_update(tabpage)
      end
    end,
  })

  vim.api.nvim_create_autocmd('TabLeave', {
    group = group,
    callback = function()
      cancel_nav(vim.api.nvim_get_current_tabpage())
    end,
  })

  vim.api.nvim_create_autocmd('TabClosed', {
    group = group,
    callback = function()
      vim.schedule(function()
        local valid_tabs = {}
        for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
          valid_tabs[tabpage] = true
        end

        for tabpage in pairs(state.get_all_sessions()) do
          if not valid_tabs[tabpage] or not vim.api.nvim_tabpage_is_valid(tabpage) then
            cancel_pending(tabpage)
            state.destroy_session(tabpage)
          end
        end
      end)
    end,
  })
end

return M
