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

---@param opts? table User configuration
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', M.defaults, opts or {})
end

return M
