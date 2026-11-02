local Paths = require('./paths')

local Formats = {}

function Formats.resolve(filename, options)
    filename = Paths.relative(filename)
    local extension = filename:match('([^/]+)$'):match('%.([^.]*)$')
    local format = options and options.format
    if format == nil then
        -- Extensionless names retain the existing versioned slot convention.
        -- Explicit filenames are recommended for newly authored games.
        if not extension or extension:lower() == 'json' then
            format = 'json'
        else
            format = 'binary'
        end
    end
    assert(
        format == 'json' or format == 'text' or format == 'binary',
        'Data format must be json, text or binary'
    )
    return format, extension ~= nil or options ~= nil and options.format ~= nil
end

return Formats
