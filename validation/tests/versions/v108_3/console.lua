-- katsa.log levels, filtering, file sink, print capture, exports and crash reports.
local Export = require('source.engine.debug.logExport')
local History = require('source.engine.debug.crashHistory')

local Module = {}

function Module.run(self)
    local log = katsa.log
    log.clear()
    log.setFile(nil)
    log.log('hello', 'test', true)
    log.warn('careful, "quoted"', 'test', true)
    log.error('boom', 'test', true)
    self:check(log.count() == 3 and log.count('warn') == 1, 'Log counts entries by level')
    self:check(#log.entries('warn') == 2, 'Warn filter keeps warnings and errors')
    self:check(#log.entries('error') == 1, 'Error filter keeps only errors')
    self:check(#log.entries(nil, 'care') == 1, 'Text filter matches plain substrings')
    local seen = {}
    local stop = log.subscribe(function(entry)
        seen[#seen + 1] = entry.message
    end)
    log.log('live', 'test', true)
    stop()
    log.log('after', 'test', true)
    self:check(#seen == 1 and seen[1] == 'live', 'Listeners receive entries until removed')
    log.setLimit(3)
    self:check(log.count() == 3 and log.entries()[1].message ~= 'hello', 'History is bounded')
    log.setLimit(2000)

    local json = Export.build(log.entries(), 'json')
    self:check(json:find('"entries"', 1, true) and json:find('after', 1, true), 'JSON export')
    log.clear()
    log.warn('a,b "c"', 'x', true)
    local csv = Export.build(log.entries(), 'csv')
    self:check(csv:find('"a,b ""c"""', 1, true) ~= nil, 'CSV export quotes cells')
    local path = Export.save(log.entries(), 'csv')
    self:check(katsa.filesystem.getInfo(path) ~= nil, 'Export is written to logs/')
    katsa.filesystem.remove(path)

    log.setFile('logs/test-console.log')
    katsa.filesystem.remove('logs/test-console.log')
    log.error('to file', 'test', true)
    log.setFile(nil)
    local text = katsa.filesystem.read('logs/test-console.log')
    self:check(text and text:find('[error] to file', 1, true), 'File sink writes .log lines')
    katsa.filesystem.remove('logs/test-console.log')

    log.capturePrint()
    print('captured', 42)
    log.releasePrint()
    local last = log.tail(1)[1]
    self:check(last.message == 'captured\t42' and last.source == 'print', 'print is captured')

    local files = {}
    local fs = {
        read = function(path)
            return files[path]
        end,
        write = function(path, data)
            files[path] = data
            return true
        end,
        createDirectory = function()
            return true
        end,
    }
    History.write(fs, 'Crash', { { utc = 'T', level = 'warn', message = 'context line' } })
    self:check(
        files['crashes/crash-01.log']:find('context line', 1, true)
            and files['last-error.log'] == files['crashes/crash-01.log'],
        'Crash report is a .log with recent console lines'
    )
    log.clear()
end

return Module
