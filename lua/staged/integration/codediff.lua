local M = {}

local state = require('staged.core.state')
local config = require('staged.config')

local wait_interval_ms = 25
local max_wait_attempts = 400
local next_wait_id = 0
local pending_waits = {}

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
  return vim.fs.normalize(path):gsub('\\', '/')
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

---@param codediff_session table
---@param modified_path string
---@return string
local function get_session_root(codediff_session, modified_path)
  local explorer_root = codediff_session.explorer and codediff_session.explorer.dir2 or nil
  if type(codediff_session.git_root) == 'string' and codediff_session.git_root ~= '' then
    return codediff_session.git_root
  end
  if type(explorer_root) == 'string' and explorer_root ~= '' then
    return explorer_root
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

---@param tabpage integer
---@param selected_path? string
local function wait_for_update(tabpage, selected_path)
  if not should_sync(tabpage) then
    return
  end

  next_wait_id = next_wait_id + 1
  local wait_id = next_wait_id
  pending_waits[tabpage] = wait_id

  local function check(attempt)
    if pending_waits[tabpage] ~= wait_id then
      return
    end

    if not vim.api.nvim_tabpage_is_valid(tabpage) then
      pending_waits[tabpage] = nil
      return
    end

    local lifecycle = get_lifecycle()
    local codediff_session = lifecycle and M.get_codediff_session(tabpage) or nil
    local path_ready = codediff_session
      and (
        not selected_path
        or selected_path_matches(lifecycle, tabpage, codediff_session, selected_path)
      )

    if codediff_session and codediff_session.stored_diff_result ~= nil and path_ready then
      pending_waits[tabpage] = nil
      sync_session(tabpage)
      return
    end

    if attempt >= max_wait_attempts then
      pending_waits[tabpage] = nil
      if codediff_session and path_ready then
        sync_session(tabpage)
      end
      return
    end

    vim.defer_fn(function()
      check(attempt + 1)
    end, wait_interval_ms)
  end

  vim.schedule(function()
    check(1)
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
  if not modified_bufnr or not vim.api.nvim_buf_is_valid(modified_bufnr) then
    return nil
  end
  if not modified_path or modified_path == '' then
    return nil
  end

  local session = state.get_session(tabpage)
  if not session then
    session = state.create_session(tabpage)
  end
  session.root = get_session_root(codediff_session, modified_path)

  state.set_current_file(session, modified_path, modified_bufnr)
  require('staged.ui.inline').render(session)
  require('staged.ui.sidebar').render(session)
  require('staged').bind_session_keymaps(tabpage)

  return session
end

---Setup autocmds to track codediff sessions
function M.setup_autocmds()
  local group = vim.api.nvim_create_augroup('staged-codediff', { clear = true })
  pending_waits = {}

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
      wait_for_update(tabpage, selected_path)
    end,
  })

  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'CodeDiffClose',
    callback = function(args)
      local tabpage = event_tabpage(args)
      if tabpage then
        pending_waits[tabpage] = nil
        state.destroy_session(tabpage)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter', 'TabEnter' }, {
    group = group,
    callback = function()
      sync_session(vim.api.nvim_get_current_tabpage())
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
            pending_waits[tabpage] = nil
            state.destroy_session(tabpage)
          end
        end
      end)
    end,
  })
end

return M
