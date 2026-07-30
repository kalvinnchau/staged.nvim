local M = {}

---@type StagedConfig
M.defaults = {
  activation = {
    mode = 'auto',
  },
  keymaps = {
    prefix = '<leader>c',
    add = 'i',
    edit = 'e',
    delete = 'd',
    clear_all = 'D',
    undo = 'u',
    redo = 'r',
    toggle_sidebar = 's',
    export_clipboard = 'y',
    export_buffer = 'b',
    export_file = 'w',
    next_comment = ']m',
    prev_comment = '[m',
  },
  sidebar = {
    position = 'left',
    width = 40,
    height = 15,
    auto_show = true,
  },
  inline = {
    style = 'sign',
    sign_icon = '>>',
    virtual_text_format = '[%d comment(s)]',
  },
  input = {
    style = 'floating',
  },
  export = {
    include_code = true,
    format = 'markdown',
  },
}

---@type StagedConfig
M.options = vim.deepcopy(M.defaults)

local enums = {
  ['activation.mode'] = { 'auto', 'manual' },
  ['sidebar.position'] = { 'left', 'right' },
  ['inline.style'] = { 'sign', 'virtual_text', 'line_highlight' },
  ['input.style'] = { 'floating', 'inline' },
  ['export.format'] = { 'markdown', 'plain', 'json' },
}

---@param name string
---@param value any
---@param allowed string[]
local function validate_enum(name, value, allowed)
  for _, expected in ipairs(allowed) do
    if value == expected then
      return
    end
  end

  error(string.format('staged.nvim: %s must be one of: %s', name, table.concat(allowed, ', ')), 3)
end

---@param name string
---@param value any
local function validate_dimension(name, value)
  if type(value) ~= 'number' or value <= 0 or value % 1 ~= 0 then
    error(string.format('staged.nvim: %s must be a positive integer', name), 3)
  end
end

---@param name string
---@param value any
local function validate_boolean(name, value)
  if type(value) ~= 'boolean' then
    error(string.format('staged.nvim: %s must be a boolean', name), 3)
  end
end

---@param name string
---@param value any
---@param allow_empty? boolean
local function validate_string(name, value, allow_empty)
  if type(value) ~= 'string' or (not allow_empty and value == '') then
    error(
      string.format('staged.nvim: %s must be a%s string', name, allow_empty and '' or ' non-empty'),
      3
    )
  end
end

---@param options StagedConfig
local function validate(options)
  for name, allowed in pairs(enums) do
    local section, option = name:match('^([^.]+)%.(.+)$')
    validate_enum(name, options[section][option], allowed)
  end

  validate_dimension('sidebar.width', options.sidebar.width)
  validate_dimension('sidebar.height', options.sidebar.height)
  validate_boolean('sidebar.auto_show', options.sidebar.auto_show)
  validate_boolean('export.include_code', options.export.include_code)

  for name in pairs(M.defaults.keymaps) do
    validate_string('keymaps.' .. name, options.keymaps[name], name == 'prefix')
  end

  validate_string('inline.sign_icon', options.inline.sign_icon)
  if vim.fn.strdisplaywidth(options.inline.sign_icon) > 2 then
    error('staged.nvim: inline.sign_icon must be at most two display cells', 3)
  end

  validate_string('inline.virtual_text_format', options.inline.virtual_text_format)
  if not pcall(string.format, options.inline.virtual_text_format, 1) then
    error('staged.nvim: inline.virtual_text_format must be a valid string.format pattern', 3)
  end
end

---@param opts? table User configuration
function M.setup(opts)
  local options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  validate(options)
  M.options = options
end

return M
