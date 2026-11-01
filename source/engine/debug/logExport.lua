-- Console export: JSON or CSV snapshots of katsa.log entries, written to `logs/` in the save
-- directory. Serialization is manual and never runs while idle.
local Json = require('vendor.json')
local Csv = require('source.engine.debug.csv')
local Version = require('source.engine.core.version')

local Export = {}
local columns = { 'id', 'utc', 'time', 'level', 'source', 'message' }

function Export.build(entries, format)
    if format == 'json' then
        local rows = {}
        for index, entry in ipairs(entries) do
            rows[index] = {
                id = entry.id,
                utc = entry.utc,
                time = entry.time,
                level = entry.level,
                source = entry.source,
                message = entry.message,
            }
        end
        return Json.encode({ schema = 1, app_version = Version.value, entries = rows })
    elseif format == 'csv' then
        local lines = { table.concat(columns, ',') }
        for _, entry in ipairs(entries) do
            local values = {}
            for index, name in ipairs(columns) do
                values[index] = entry[name]
            end
            lines[#lines + 1] = Csv.row(values, #columns)
        end
        return table.concat(lines, '\r\n') .. '\r\n'
    end
    error('Unknown log export format: ' .. tostring(format))
end

function Export.save(entries, format)
    local data = Export.build(entries, format)
    assert(katsa.filesystem.createDirectory('logs'), 'Could not create the logs directory')
    local stem = 'logs/console-' .. os.date('!%Y%m%dT%H%M%SZ')
    local path, index = stem .. '.' .. format, 1
    while katsa.filesystem.getInfo(path) do
        path = stem .. '-' .. index .. '.' .. format
        index = index + 1
    end
    assert(katsa.filesystem.write(path, data))
    return path
end

return Export
