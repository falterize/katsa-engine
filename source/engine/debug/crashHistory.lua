local History = {}

local SLOTS = 10

-- Report text: UTC time, traceback, then the most recent console lines (if any) for context.
local function report(traceback, recent)
    local lines = { os.date('!%Y-%m-%dT%H:%M:%SZ'), '', traceback }
    if recent and #recent > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = '--- recent log ---'
        for _, entry in ipairs(recent) do
            lines[#lines + 1] = string.format('%s [%s] %s', entry.utc, entry.level, entry.message)
        end
    end
    return table.concat(lines, '\n')
end

-- Fixed slots `crashes/crash-NN.log` (01 newest) keep retention deterministic even when several
-- errors share a timestamp. `last-error.log` always holds the newest report.
function History.write(filesystem, traceback, recent)
    local text = report(traceback, recent)
    filesystem.write('last-error.log', text)
    if not filesystem.createDirectory or not filesystem.read then
        return
    end
    assert(filesystem.createDirectory('crashes'))
    for index = SLOTS - 1, 1, -1 do
        local old = filesystem.read(string.format('crashes/crash-%02d.log', index))
        if old then
            assert(filesystem.write(string.format('crashes/crash-%02d.log', index + 1), old))
        end
    end
    assert(filesystem.write('crashes/crash-01.log', text))
end

return History
