-- Per-run log files: `logs/latest.log` is the current run, `logs/previous.log` the one before.
local Session = {}

function Session.start()
    local fs = katsa.filesystem
    if fs.createDirectory('logs') then
        local previous = fs.read('logs/latest.log')
        if previous then
            fs.write('logs/previous.log', previous)
        end
        fs.write('logs/latest.log', '')
        katsa.log.setFile('logs/latest.log')
    end
    katsa.log.capturePrint()
end

return Session
