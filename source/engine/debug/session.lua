-- Per-run log files: `logs/latest.log` is the current run, `logs/previous.log` the one before.
local Session = {}

-- `name` gives a process of its own (a server started by the game) separate files
-- (`logs/server-latest.log`), so it never truncates or interleaves the log of the game that started it.
function Session.start(name)
    local fs = katsa.filesystem
    local prefix = name and (name .. '-') or ''
    if fs.createDirectory('logs') then
        local previous = fs.read('logs/' .. prefix .. 'latest.log')
        if previous then
            fs.write('logs/' .. prefix .. 'previous.log', previous)
        end
        fs.write('logs/' .. prefix .. 'latest.log', '')
        katsa.log.setFile('logs/' .. prefix .. 'latest.log')
    end
    katsa.log.capturePrint()
end

return Session
