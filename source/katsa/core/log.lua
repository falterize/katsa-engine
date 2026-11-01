-- katsa.log: leveled log with a bounded in-memory history, live listeners and an optional
-- `.log` file in the save directory. Levels: 'log', 'warn', 'error'. Host output goes to
-- stdout (log) and stderr (warn/error) so a launcher can pipe it.
local Log = {}

local LEVELS = { log = 1, warn = 2, error = 3 }
local limit, sequence = 2000, 0
local entries, listeners = {}, {}
local filePath
local originalPrint

Log.levels = LEVELS

local function stamp()
    return os.date('!%Y-%m-%dT%H:%M:%SZ')
end

local function toFile(entry)
    if not filePath then
        return
    end
    -- A failing sink must never raise into the code that is logging.
    pcall(
        katsa.filesystem.append,
        filePath,
        string.format('%s [%s] %s\n', entry.utc, entry.level, entry.message)
    )
end

local function toStream(entry)
    local stream = entry.level == 'log' and io.stdout or io.stderr
    stream:write(entry.message, '\n')
end

-- `silent` skips the stdout/stderr echo (the caller already printed the text).
function Log.write(level, message, source, silent)
    assert(LEVELS[level], 'Unknown log level: ' .. tostring(level))
    sequence = sequence + 1
    local entry = {
        id = sequence,
        level = level,
        message = tostring(message),
        source = source or '',
        time = katsa.timer.getTime(),
        utc = stamp(),
    }
    entries[#entries + 1] = entry
    if #entries > limit then
        table.remove(entries, 1)
    end
    toFile(entry)
    if not silent then
        toStream(entry)
    end
    for _, listener in ipairs(listeners) do
        listener(entry)
    end
    return entry
end

for level in pairs(LEVELS) do
    Log[level] = function(message, source, silent)
        return Log.write(level, message, source, silent)
    end
end

-- Entries at or above `minimum` (default all), optionally containing `text` (plain match).
function Log.entries(minimum, text)
    local floor = minimum and LEVELS[minimum] or 1
    local result = {}
    for _, entry in ipairs(entries) do
        if LEVELS[entry.level] >= floor and (not text or entry.message:find(text, 1, true)) then
            result[#result + 1] = entry
        end
    end
    return result
end

-- The newest `count` entries, oldest first.
function Log.tail(count)
    local result = {}
    for index = math.max(1, #entries - count + 1), #entries do
        result[#result + 1] = entries[index]
    end
    return result
end

function Log.count(level)
    local total = 0
    for _, entry in ipairs(entries) do
        if not level or entry.level == level then
            total = total + 1
        end
    end
    return total
end

function Log.clear()
    entries = {}
end

function Log.setLimit(value)
    assert(type(value) == 'number' and value >= 1, 'Log limit must be at least 1')
    limit = math.floor(value)
    while #entries > limit do
        table.remove(entries, 1)
    end
end

-- Returns a function that removes the listener.
function Log.subscribe(listener)
    listeners[#listeners + 1] = listener
    return function()
        for index, item in ipairs(listeners) do
            if item == listener then
                table.remove(listeners, index)
                return
            end
        end
    end
end

-- Appends every entry to `path` in the save directory; nil stops file logging.
function Log.setFile(path)
    filePath = path
end

function Log.getFile()
    return filePath
end

-- Routes the global print into the log (level 'log') while still printing.
function Log.capturePrint()
    if originalPrint then
        return
    end
    originalPrint = print
    print = function(...)
        local parts = {}
        for index = 1, select('#', ...) do
            parts[index] = tostring((select(index, ...)))
        end
        originalPrint(...)
        Log.write('log', table.concat(parts, '\t'), 'print', true)
    end
end

function Log.releasePrint()
    if originalPrint then
        print = originalPrint
        originalPrint = nil
    end
end

return Log
