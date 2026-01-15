local M = {}

local state = require('staged.core.state')
local config = require('staged.config')

---Check if codediff.nvim is available
---@return boolean
function M.is_available()
  local ok = pcall(require, 'codediff.ui.lifecycle')
  return ok
end

---Get codediff session for a tabpage
---@param tabpage integer
---@return table|nil codediff session
function M.get_codediff_session(tabpage)
  local ok, lifecycle = pcall(require, 'codediff.ui.lifecycle')
  if not ok then
    return nil
  end

  return lifecycle.get_session(tabpage)
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
  local codediff_session = M.get_codediff_session(tabpage)
  if not codediff_session then
    return nil
  end

  -- Get modified buffer info from codediff
  local modified_bufnr = codediff_session.modified_bufnr
  local modified_path = codediff_session.modified_path

  -- Wait until codediff has valid buffer info
  if not modified_bufnr or not vim.api.nvim_buf_is_valid(modified_bufnr) then
    return nil
  end
  if not modified_path or modified_path == '' then
    return nil
  end

  -- Get or create staged session
  local session = state.get_session(tabpage)
  if not session then
    session = state.create_session(tabpage)
  end

  -- Update current file (handles file switches in codediff)
  state.set_current_file(session, modified_path, modified_bufnr)

  -- Re-render inline indicators for the current file
  local inline = require('staged.ui.inline')
  inline.render(session)

  return session
end

---Setup autocmds to track codediff sessions
function M.setup_autocmds()
  local group = vim.api.nvim_create_augroup('staged-codediff', { clear = true })

  local function try_init()
    if config.options.activation.mode ~= 'auto' then
      return
    end

    local tabpage = vim.api.nvim_get_current_tabpage()
    local codediff_session = M.get_codediff_session(tabpage)

    if codediff_session then
      M.init_for_codediff(tabpage)
    end
  end

  -- When entering a tab, check if it's a codediff and initialize
  vim.api.nvim_create_autocmd('TabEnter', {
    group = group,
    callback = try_init,
  })

  -- Also check on BufEnter since codediff session may be created after TabEnter
  -- This handles file switches within a codediff session
  vim.api.nvim_create_autocmd('BufEnter', {
    group = group,
    callback = try_init,
  })

  -- Clean up when tab closes
  vim.api.nvim_create_autocmd('TabClosed', {
    group = group,
    callback = function(args)
      -- args.file contains the closed tabpage number as string
      local tabpage = tonumber(args.file)
      if tabpage then
        state.destroy_session(tabpage)
      end
    end,
  })
end

return M
