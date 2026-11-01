-- Engine version. `value` is the release tag ("v108.4"): major 108, minor 4.
-- Projects and scenes may declare the engine version they were made for (`version = 'v108.4'`);
-- compatible() tells a launcher or the loader whether that declaration matches this engine.
local Version = { name = 'Katsa', value = 'v108.4' }

-- "v108.4", "108.4" or "v108" -> { major, minor }, or nil when unreadable.
function Version.parse(text)
    if type(text) ~= 'string' then
        return nil
    end
    local major, minor = text:match('^v?(%d+)%.?(%d*)$')
    if not major then
        return nil
    end
    return { tonumber(major), tonumber(minor) or 0 }
end

-- -1 when a is older than b, 0 when equal, 1 when newer; nil if either is unreadable.
function Version.compare(a, b)
    a, b = Version.parse(a), Version.parse(b)
    if not (a and b) then
        return nil
    end
    for index = 1, 2 do
        if a[index] ~= b[index] then
            return a[index] < b[index] and -1 or 1
        end
    end
    return 0
end

-- Returns status, message. Status: 'same', 'older' (made for an earlier engine; usually fine),
-- 'newer' (made for a later engine; may use features this one lacks), 'unknown' (no/invalid
-- declaration). `current` defaults to this engine.
function Version.compatible(declared, current)
    current = current or Version.value
    if declared == nil then
        return 'unknown', 'No engine version declared'
    end
    local order = Version.compare(declared, current)
    if order == nil then
        return 'unknown', ('Unreadable engine version %q'):format(tostring(declared))
    elseif order == 0 then
        return 'same'
    elseif order < 0 then
        return 'older', ('Made for engine %s; running %s'):format(declared, current)
    end
    return 'newer', ('Made for engine %s, newer than the running %s'):format(declared, current)
end

return Version
