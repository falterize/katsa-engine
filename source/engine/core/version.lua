-- Engine version. `release` is the version number scenes and projects compare against; `value`
-- stays the release tag used for builds and file names ("v108.4").
-- Format: MAJOR.MINOR.PATCH with an optional stage letter: 1.0.0a (alpha), 1.0.0b (beta),
-- 1.0.0rc (release candidate); no letter means a stable release.
-- Projects and scenes may declare the engine they were made for (`version = '1.0.0a'`);
-- compatible() tells a launcher or the loader whether that declaration matches this engine.
local Version = { name = 'Katsa', value = 'v108.4', release = '1.0.0a' }

local STAGES = { a = 1, b = 2, rc = 3, [''] = 4 }
Version.stageNames = { a = 'alpha', b = 'beta', rc = 'release candidate', [''] = 'stable' }

-- "1.0.0a" -> { major, minor, patch, stage = 'a' }, or nil when unreadable. Minor and patch
-- may be omitted ("1", "1.2").
function Version.parse(text)
    if type(text) ~= 'string' then
        return nil
    end
    local major, minor, patch, stage = text:match('^(%d+)%.?(%d*)%.?(%d*)(%a*)$')
    if not major or STAGES[stage] == nil then
        return nil
    end
    return {
        tonumber(major),
        tonumber(minor) or 0,
        tonumber(patch) or 0,
        stage = stage,
    }
end

-- -1 when a is older than b, 0 when equal, 1 when newer; nil if either is unreadable.
-- Within one number alpha < beta < rc < stable.
function Version.compare(a, b)
    a, b = Version.parse(a), Version.parse(b)
    if not (a and b) then
        return nil
    end
    for index = 1, 3 do
        if a[index] ~= b[index] then
            return a[index] < b[index] and -1 or 1
        end
    end
    if a.stage ~= b.stage then
        return STAGES[a.stage] < STAGES[b.stage] and -1 or 1
    end
    return 0
end

-- Returns status, message. Status: 'same', 'older' (made for an earlier engine; usually fine),
-- 'newer' (made for a later engine; may use features this one lacks), 'unknown' (no/invalid
-- declaration). `current` defaults to this engine's release.
function Version.compatible(declared, current)
    current = current or Version.release
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
