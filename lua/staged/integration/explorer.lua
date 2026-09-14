local M = {}

local state = require('staged.core.state')
local wrappers = setmetatable({}, { __mode = 'k' })
local pending = {}
local attached = {}
local rendering_tab

local function panel_view(tabpage)
  return require('staged.integration.codediff').get_panel_view(tabpage)
end

local function installed()
  local ok, config = pcall(require, 'codediff.config')
  local formatters = ok and config.options.explorer.formatters
  if type(formatters) == 'table' then
    for _, kind in ipairs({ 'file', 'folder', 'group' }) do
      if wrappers[formatters[kind]] then
        return true
      end
    end
  end
  return false
end

local function resolve_tabpage(ctx, opts)
  if opts.resolve_tabpage then
    return opts.resolve_tabpage(ctx)
  end
  if opts.tabpage then
    return opts.tabpage
  end
  if rendering_tab then
    return rendering_tab
  end
  -- Upstream row contexts lack a tab handle. Outside our controlled redraw,
  -- only a matching explorer buffer provides an unambiguous owner.
  local buf = vim.api.nvim_get_current_buf()
  for tabpage in pairs(state.get_all_sessions()) do
    local panel = panel_view(tabpage)
    if panel and panel.bufnr == buf then
      return tabpage
    end
  end
end

local function count_file(session, panel, file)
  if type(file.path) ~= 'string' then
    return 0
  end
  local revision = require('staged.integration.codediff').revision_for_group(panel, file.group)
  local path = vim.fs.normalize(vim.fs.joinpath(session.root, file.path))
  local file_state = session.files[state.file_key(path, { modified_revision = revision })]
  return file_state and vim.tbl_count(file_state.comments) or 0
end

---Wrap codediff's configured/default row formatters without modifying its config.
---@param opts? {file?: function, folder?: function, group?: function, tabpage?: integer, resolve_tabpage?: fun(ctx: table): integer|nil}
---@return table<string, function>
function M.formatters(opts)
  opts = opts or {}
  local defaults = require('codediff.ui.explorer.formatters')
  local result = {}
  for _, kind in ipairs({ 'file', 'folder', 'group' }) do
    local original = opts[kind] or defaults[kind]
    result[kind] = function(ctx)
      local layout = original(ctx)
      local tabpage = resolve_tabpage(ctx, opts)
      local session = tabpage and state.get_session(tabpage)
      local panel = session and panel_view(tabpage)
      if not panel or type(layout) ~= 'table' then
        return layout
      end
      local count = 0
      if kind == 'file' then
        count = count_file(session, panel, ctx)
      else
        for _, file in ipairs(ctx.files or {}) do
          count = count + count_file(session, panel, file)
        end
      end
      if count == 0 then
        return layout
      end
      layout = vim.deepcopy(layout)
      layout.right = layout.right or {}
      table.insert(layout.right, {
        segments = { { text = ' comments:' .. count, hl = 'Comment' } },
      })
      return layout
    end
    wrappers[result[kind]] = true
  end
  return result
end

local refresh

local function watch(panel, tabpage)
  if attached[panel.bufnr] then
    return
  end
  attached[panel.bufnr] = vim.api.nvim_buf_attach(panel.bufnr, false, {
    on_lines = function(_, buf)
      if not state.get_session(tabpage) or not installed() then
        attached[buf] = nil
        return true
      end
      if rendering_tab ~= tabpage then
        refresh(tabpage)
      end
    end,
    on_detach = function(_, buf)
      attached[buf] = nil
    end,
  })
end

refresh = function(tabpage)
  if pending[tabpage] or not installed() then
    return
  end
  local session = state.get_session(tabpage)
  if not session then
    return
  end
  pending[tabpage] = session
  vim.schedule(function()
    if pending[tabpage] ~= session then
      return
    end
    pending[tabpage] = nil
    if
      state.get_session(tabpage) ~= session
      or not vim.api.nvim_tabpage_is_valid(tabpage)
      or not installed()
    then
      return
    end
    local panel = panel_view(tabpage)
    if
      not panel
      or not panel.tree
      or type(panel.tree.render) ~= 'function'
      or not panel.bufnr
      or not vim.api.nvim_buf_is_valid(panel.bufnr)
    then
      return
    end
    watch(panel, tabpage)
    -- A buffer observer schedules a corrective redraw after upstream renders
    -- without a tab context; our own writes do not schedule another redraw.
    local previous = rendering_tab
    rendering_tab = tabpage
    local ok, err = pcall(panel.tree.render, panel.tree)
    rendering_tab = previous
    if not ok then
      vim.notify(
        'staged.nvim: could not refresh comment badges: ' .. tostring(err),
        vim.log.levels.WARN
      )
    end
  end)
end

function M.setup()
  local group = vim.api.nvim_create_augroup('staged-explorer-badges', { clear = true })
  pending = {}
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = { 'StagedCommentsChanged', 'CodeDiffOpen', 'CodeDiffFileSelect' },
    callback = function(args)
      local tabpage = args.data and args.data.tabpage
      if type(tabpage) == 'number' then
        refresh(tabpage)
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufEnter', {
    group = group,
    callback = function()
      refresh(vim.api.nvim_get_current_tabpage())
    end,
  })
end

return M
