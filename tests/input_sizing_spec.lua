local helpers = require('tests.helpers')

describe('input sizing', function()
  local input = require('staged.ui.input')
  local config = require('staged.config')

  local test_buf
  local original_lines, original_columns

  local function flush_scheduled()
    local done = false
    vim.schedule(function()
      done = true
    end)
    assert.is_true(vim.wait(500, function()
      return done
    end))
  end

  local function open_input(opts)
    local result = { text = 'NOT_CALLED', calls = 0 }
    input.open_floating(opts or {}, function(text)
      result.text = text
      result.calls = result.calls + 1
    end)
    -- Close callbacks are often vim.scheduled; flush pending scheduled work
    flush_scheduled()
    return result
  end

  before_each(function()
    original_lines, original_columns = vim.o.lines, vim.o.columns
    test_buf = helpers.create_test_buffer(helpers.default_lines)
    vim.api.nvim_set_current_buf(test_buf)
    -- Deterministic small-ish viewport
    vim.api.nvim_set_option_value('lines', 30, { scope = 'global' })
    vim.api.nvim_set_option_value('columns', 100, { scope = 'global' })
    vim.cmd('mode')
    vim.cmd('stopinsert')
  end)

  after_each(function()
    -- Close any leftover floating windows
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative ~= '' then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    vim.o.lines, vim.o.columns = original_lines, original_columns
    helpers.cleanup_session()
    if vim.api.nvim_buf_is_valid(test_buf) then
      vim.api.nvim_buf_delete(test_buf, { force = true })
    end
  end)

  local function get_float_win()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative ~= '' then
        return win
      end
    end
    return nil
  end

  local function get_float_buf(win)
    return vim.api.nvim_win_get_buf(win)
  end

  describe('initial sizing', function()
    it('measures height from initial multiline content', function()
      open_input({ initial_text = 'line one\nline two\nline three\nline four' })

      local win = get_float_win()
      assert.is_not_nil(win)

      local buf = get_float_buf(win)
      -- 4 logical lines fit in a 5-high window untouched
      assert.equals(5, vim.api.nvim_win_get_height(win))

      local line_count = vim.api.nvim_buf_line_count(buf)
      assert.equals(4, line_count)
    end)

    it('grows beyond default height for long multiline initial text', function()
      local many_lines = {}
      for i = 1, 10 do
        table.insert(many_lines, 'line ' .. i)
      end
      open_input({ initial_text = table.concat(many_lines, '\n') })

      local win = get_float_win()
      assert.is_not_nil(win)

      local height = vim.api.nvim_win_get_height(win)
      assert.is_true(height >= 10, ('expected height >= 10 for 10 lines, got %d'):format(height))
    end)

    it('accounts for wrapping of long single-line content', function()
      local long_line = string.rep('x', 200)
      open_input({ initial_text = long_line })

      local win = get_float_win()
      assert.is_not_nil(win)

      local width = vim.api.nvim_win_get_width(win)
      local height = vim.api.nvim_win_get_height(win)
      -- 200 chars in a 60-wide window wraps to at least 4 screen lines
      assert.is_true(
        height >= math.ceil(200 / width),
        ('expected wrapped height >= %d, got %d'):format(math.ceil(200 / width), height)
      )
    end)

    it('clamps height to small viewport', function()
      vim.api.nvim_set_option_value('lines', 10, { scope = 'global' })
      vim.cmd('mode')

      local many_lines = {}
      for i = 1, 20 do
        table.insert(many_lines, 'line ' .. i)
      end
      open_input({ initial_text = table.concat(many_lines, '\n') })

      local win = get_float_win()
      assert.is_not_nil(win)

      local height = vim.api.nvim_win_get_height(win)
      -- Window (content + 2 border rows) must fit in the 10-line viewport
      assert.is_true(height + 2 <= 10, ('expected height + 2 <= 10, got %d'):format(height))
      assert.is_true(height >= 1)
    end)

    it('clamps width to narrow viewport', function()
      vim.api.nvim_set_option_value('columns', 40, { scope = 'global' })
      vim.cmd('mode')

      open_input({})

      local win = get_float_win()
      assert.is_not_nil(win)

      local width = vim.api.nvim_win_get_width(win)
      assert.is_true(width + 2 <= 40, ('expected width + 2 <= 40, got %d'):format(width))
      assert.is_true(width >= 1)
    end)
  end)

  describe('dynamic resize while typing', function()
    it('grows when text is added', function()
      open_input({ initial_text = 'short' })

      local win = get_float_win()
      assert.is_not_nil(win)
      local buf = get_float_buf(win)

      local height_before = vim.api.nvim_win_get_height(win)

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        'short',
        'second line',
        'third line',
        'fourth line',
        'fifth line',
        'sixth line',
      })
      vim.cmd('doautocmd TextChanged')

      vim.wait(100, function()
        return vim.api.nvim_win_get_height(win) > height_before
      end)

      assert.is_true(
        vim.api.nvim_win_get_height(win) > height_before,
        'expected window to grow after adding lines'
      )
    end)

    it('shrinks when text is removed', function()
      local many_lines = {}
      for i = 1, 12 do
        table.insert(many_lines, 'line ' .. i)
      end
      open_input({ initial_text = table.concat(many_lines, '\n') })

      local win = get_float_win()
      assert.is_not_nil(win)
      local buf = get_float_buf(win)

      local height_before = vim.api.nvim_win_get_height(win)

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'tiny' })
      vim.cmd('doautocmd TextChanged')

      vim.wait(100, function()
        return vim.api.nvim_win_get_height(win) < height_before
      end)

      assert.is_true(
        vim.api.nvim_win_get_height(win) < height_before,
        'expected window to shrink after removing lines'
      )
    end)
  end)

  local function press(key)
    -- 'x' flag: execute typeahead now, so buffer-local mappings fire even in
    -- headless tests where async input is never processed
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), 'x', false)
  end

  describe('cancel/close/wipe cleanup', function()
    it('closes cleanly on cancel and calls callback with nil', function()
      local result = open_input({ initial_text = 'will cancel' })

      local win = get_float_win()
      assert.is_not_nil(win)

      -- First <Esc> leaves Insert mode, second triggers the Normal-mode keymap
      press('<Esc>')
      press('<Esc>')

      vim.wait(300, function()
        return result.text ~= 'NOT_CALLED'
      end)
      assert.equals(nil, result.text)

      vim.wait(100, function()
        return get_float_win() == nil
      end)
      assert.is_nil(get_float_win())
    end)

    it('closes cleanly on confirm and returns trimmed text', function()
      local result = open_input({ initial_text = '  my comment  ' })

      local win = get_float_win()
      assert.is_not_nil(win)

      -- <C-s> is mapped in both modes and closes from Insert directly
      press('<C-s>')

      vim.wait(300, function()
        return result.text ~= 'NOT_CALLED'
      end)
      assert.equals('my comment', result.text)
      assert.is_nil(get_float_win())
    end)

    it('invokes callback exactly once on wipe and clears autocmds', function()
      local result = open_input({ initial_text = 'to be wiped' })

      local win = get_float_win()
      assert.is_not_nil(win)
      local buf = get_float_buf(win)

      vim.api.nvim_buf_delete(buf, { force = true })

      vim.wait(100, function()
        return result.text ~= 'NOT_CALLED'
      end)
      assert.equals(nil, result.text)

      -- Should not fire a second time
      flush_scheduled()
      assert.equals(1, result.calls)
      assert.equals(nil, result.text)
      assert.is_nil(get_float_win())
    end)

    it('does not error when confirming after window was closed externally', function()
      local result = open_input({})

      local win = get_float_win()
      assert.is_not_nil(win)
      local buf = get_float_buf(win)

      vim.api.nvim_win_close(win, true)

      vim.wait(100, function()
        return result.text ~= 'NOT_CALLED'
      end)
      assert.equals(nil, result.text)

      -- Buffer is wiped when its last floating window closes
      vim.wait(100, function()
        return not vim.api.nvim_buf_is_valid(buf)
      end)
      assert.is_false(vim.api.nvim_buf_is_valid(buf))
    end)
  end)
end)
