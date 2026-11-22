-- Per-run log files: `logs/latest.log` is the current run, `logs/previous.log` the one before.
-- `logs/running` exists while a run is alive in the foreground; finding it at the next start means
-- the previous run was killed (a crash, a hang the system ended, a lost power button...).
local Session = {}

local function marker(name)
    return 'logs/' .. (name and (name .. '-') or '') .. 'running'
end

-- `name` gives a process of its own (a server started by the game) separate files
-- (`logs/server-latest.log`), so it never truncates or interleaves the log of the game that started it.
-- Returns true when the previous run did not end cleanly.
function Session.start(name)
    local fs = katsa.filesystem
    local prefix = name and (name .. '-') or ''
    local interrupted = false
    if fs.createDirectory('logs') then
        interrupted = fs.getInfo(marker(name)) ~= nil
        local previous = fs.read('logs/' .. prefix .. 'latest.log')
        if previous then
            fs.write('logs/' .. prefix .. 'previous.log', previous)
        end
        fs.write('logs/' .. prefix .. 'latest.log', '')
        katsa.log.setFile('logs/' .. prefix .. 'latest.log')
        Session.mark(name, true)
    end
    katsa.log.capturePrint()
    return interrupted
end

-- A run in the background (or finished) is not "killed while running": the marker is removed then
-- and written again when the window returns.
function Session.mark(name, running)
    local fs = katsa.filesystem
    if running then
        fs.write(marker(name), '')
    else
        fs.remove(marker(name))
    end
end

return Session
