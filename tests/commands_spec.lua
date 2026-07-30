describe('commands', function()
  local staged = require('staged')
  local export = require('staged.export')

  local original
  local calls

  before_each(function()
    original = {
      undo = staged.undo,
      redo = staged.redo,
      to_clipboard = export.to_clipboard,
      to_buffer = export.to_buffer,
      to_file = export.to_file,
      notify = vim.notify,
    }
    calls = {}

    staged.undo = function()
      table.insert(calls, { name = 'undo' })
    end
    staged.redo = function()
      table.insert(calls, { name = 'redo' })
    end
    export.to_clipboard = function(opts)
      table.insert(calls, { name = 'clipboard', opts = opts })
    end
    export.to_buffer = function(opts)
      table.insert(calls, { name = 'buffer', opts = opts })
    end
    export.to_file = function(path, opts)
      table.insert(calls, { name = 'file', path = path, opts = opts })
    end
    vim.notify = function(message, level)
      table.insert(calls, { name = 'notify', message = message, level = level })
    end
  end)

  after_each(function()
    staged.undo = original.undo
    staged.redo = original.redo
    export.to_clipboard = original.to_clipboard
    export.to_buffer = original.to_buffer
    export.to_file = original.to_file
    vim.notify = original.notify
  end)

  it('exposes undo and redo commands', function()
    vim.cmd('StagedUndo')
    vim.cmd('StagedRedo')

    assert.same({ 'undo', 'redo' }, { calls[1].name, calls[2].name })
  end)

  it('exports to a destination with an explicit format', function()
    vim.cmd('StagedExport buffer json')
    vim.cmd('StagedExport file plain')

    assert.same({ name = 'buffer', opts = { format = 'json' } }, calls[1])
    assert.same({ name = 'file', opts = { format = 'plain' } }, calls[2])
  end)

  it('keeps clipboard and configured format as defaults', function()
    vim.cmd('StagedExport')

    assert.same({ name = 'clipboard' }, calls[1])
  end)

  it('rejects invalid export arguments', function()
    vim.cmd('StagedExport quickfix')
    vim.cmd('StagedExport buffer yaml')
    vim.cmd('StagedExport buffer json extra')

    assert.equals(3, #calls)
    assert.equals('Unknown destination: quickfix', calls[1].message)
    assert.equals('Unknown format: yaml', calls[2].message)
    assert.equals('Usage: StagedExport [destination] [format]', calls[3].message)
  end)
end)
