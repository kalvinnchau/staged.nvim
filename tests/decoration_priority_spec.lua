local helpers = require('tests.helpers')

describe('decoration priority', function()
  local config = require('staged.config')
  local inline = require('staged.ui.inline')

  local test_buf
  local session
  local original_options

  before_each(function()
    original_options = vim.deepcopy(config.options)
    test_buf = helpers.create_test_buffer(helpers.default_lines)
    session = helpers.create_mock_session(test_buf, '/test/file.lua')
  end)

  after_each(function()
    config.options = original_options
    helpers.cleanup_session()
    if vim.api.nvim_buf_is_valid(test_buf) then
      vim.api.nvim_buf_delete(test_buf, { force = true })
    end
  end)

  local function get_marks()
    return vim.api.nvim_buf_get_extmarks(test_buf, session.indicator_ns_id, 0, -1, {
      details = true,
    })
  end

  describe('config validation', function()
    it('defaults inline.priority to 150', function()
      assert.equals(150, config.options.inline.priority)
    end)

    it('accepts boundary values 0 and 65535', function()
      config.setup({ inline = { priority = 0 } })
      assert.equals(0, config.options.inline.priority)

      config.setup({ inline = { priority = 65535 } })
      assert.equals(65535, config.options.inline.priority)
    end)

    it('rejects priority above 65535', function()
      assert.has_error(function()
        config.setup({ inline = { priority = 65536 } })
      end)
    end)

    it('rejects negative priority', function()
      assert.has_error(function()
        config.setup({ inline = { priority = -1 } })
      end)
    end)

    it('rejects non-integer priority', function()
      assert.has_error(function()
        config.setup({ inline = { priority = 1.5 } })
      end)
    end)

    it('rejects non-number priority', function()
      assert.has_error(function()
        config.setup({ inline = { priority = '150' } })
      end)
      -- nil reverts to the default via tbl_deep_extend rather than erroring
      config.setup({ inline = { priority = nil } })
      assert.equals(150, config.options.inline.priority)
    end)
  end)

  describe('extmark application', function()
    it('applies priority to sign extmarks', function()
      config.options.inline.priority = 200
      helpers.add_comment(3, 3, 'Sign comment')
      inline.render(session)

      local signs = helpers.get_signs(test_buf, session)
      assert.equals(1, #signs)

      local marks = get_marks()
      assert.equals(1, #marks)
      assert.equals(200, marks[1][4].priority)
    end)

    it('applies priority to virtual text extmarks', function()
      config.options.inline.style = 'virtual_text'
      config.options.inline.priority = 42
      helpers.add_comment(3, 3, 'Virt text comment')
      inline.render(session)

      local marks = get_marks()
      assert.equals(1, #marks)
      assert.is_not_nil(marks[1][4].virt_text)
      assert.equals(42, marks[1][4].priority)
    end)

    it('applies priority to line highlight extmarks', function()
      config.options.inline.style = 'line_highlight'
      config.options.inline.priority = 99
      helpers.add_comment(3, 3, 'Highlight comment')
      inline.render(session)

      local marks = get_marks()
      assert.equals(1, #marks)
      assert.is_not_nil(marks[1][4].line_hl_group)
      assert.equals(99, marks[1][4].priority)
    end)

    it('applies configured priority on re-render', function()
      helpers.add_comment(3, 3, 'Re-render')
      inline.render(session)
      config.options.inline.priority = 300
      inline.render(session)

      local marks = get_marks()
      assert.equals(1, #marks)
      assert.equals(300, marks[1][4].priority)
    end)

    it('default priority stays below upstream moved-block priority 250', function()
      assert.is_true(config.options.inline.priority < 250)
    end)
  end)

  describe('interaction with other extmarks', function()
    it('does not modify extmarks in other namespaces', function()
      local other_ns = vim.api.nvim_create_namespace('other-plugin')

      local other_id = vim.api.nvim_buf_set_extmark(test_buf, other_ns, 2, 0, {
        virt_text = { { 'OTHER', 'Comment' } },
        priority = 250,
      })

      config.options.inline.priority = 150
      helpers.add_comment(3, 3, 'With other extmark')
      inline.render(session)

      local other_mark = vim.api.nvim_buf_get_extmark_by_id(test_buf, other_ns, other_id, {
        details = true,
      })
      assert.is_not_nil(other_mark)
      assert.equals(250, other_mark[3].priority)
      assert.is_not_nil(other_mark[3].virt_text)
    end)

    it('coexists with higher-priority extmark on same line', function()
      local high_ns = vim.api.nvim_create_namespace('high-priority')

      vim.api.nvim_buf_set_extmark(test_buf, high_ns, 2, 0, {
        virt_text = { { 'HIGH', 'Error' } },
        priority = 250,
      })

      config.options.inline.style = 'virtual_text'
      config.options.inline.priority = 150
      helpers.add_comment(3, 3, 'Lower priority')
      inline.render(session)

      -- Both extmarks exist; ours carries the lower configured priority
      local marks = get_marks()
      assert.equals(1, #marks)
      assert.equals(150, marks[1][4].priority)

      local high_marks = vim.api.nvim_buf_get_extmarks(test_buf, high_ns, 0, -1, {
        details = true,
      })
      assert.equals(1, #high_marks)
      assert.equals(250, high_marks[1][4].priority)
    end)
  end)
end)
