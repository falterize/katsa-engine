local Saves = {}

function Saves.read(data, filename, legacySlot, options)
    local value, metadata = data:read(filename, options)
    if not value or metadata.status ~= 'new' or not data:exists(legacySlot) then
        return value, metadata
    end
    -- Copy the existing demo slot once; failed/corrupt reads never overwrite it.
    value, metadata = data:read(legacySlot, options)
    if not value then
        return nil, metadata
    end
    local committed, failure = data:write(filename, value, options)
    if not committed then
        return nil, failure
    end
    return value, metadata
end

return Saves
