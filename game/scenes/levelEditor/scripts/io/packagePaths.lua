-- Pure helpers that move asset paths between the editor store (`editor/assets/...`) and the
-- package (`assets/...`), and that strip values a location file cannot hold.
local PackagePaths = {}

-- Deep copy of `value` with every string that starts with `from` rewritten to start with `to`.
function PackagePaths.rewrite(value, from, to)
    if type(value) == 'string' then
        if value:sub(1, #from) == from then
            return to .. value:sub(#from + 1)
        end
        return value
    elseif type(value) == 'table' then
        local result = {}
        for key, item in pairs(value) do
            result[key] = PackagePaths.rewrite(item, from, to)
        end
        return result
    end
    return value
end

-- Adds every string under `value` that starts with `prefix` to `out` (a set).
function PackagePaths.collect(value, prefix, out)
    if type(value) == 'string' then
        if value:sub(1, #prefix) == prefix then
            out[value] = true
        end
    elseif type(value) == 'table' then
        for _, item in pairs(value) do
            PackagePaths.collect(item, prefix, out)
        end
    end
    return out
end

-- A copy holding only numbers, strings, booleans and tables of those (engine vectors become arrays); returns the copy and the
-- number of dropped values (functions, userdata, NaN/inf, cyclic references).
function PackagePaths.sanitize(value, seen)
    seen = seen or {}
    local kind = type(value)
    if kind == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then
            return nil, 1
        end
        return value, 0
    elseif kind == 'string' or kind == 'boolean' then
        return value, 0
    elseif kind == 'userdata' then
        -- Engine vectors and colours (position, size, color...) are userdata with numeric
        -- components; a file holds them as plain arrays.
        local ok, count = pcall(function()
            return #value
        end)
        if not ok or type(count) ~= 'number' or count < 2 or count > 4 then
            return nil, 1
        end
        local result = {}
        for index = 1, count do
            local component = value[index]
            if type(component) ~= 'number' or component ~= component or component == math.huge or component == -math.huge then
                return nil, 1
            end
            result[index] = component
        end
        return result, 0
    elseif kind == 'table' then
        if seen[value] then
            return nil, 1
        end
        seen[value] = true
        local result, dropped = {}, 0
        for key, item in pairs(value) do
            if type(key) == 'string' or type(key) == 'number' then
                local clean, lost = PackagePaths.sanitize(item, seen)
                result[key] = clean
                dropped = dropped + lost
            else
                dropped = dropped + 1
            end
        end
        seen[value] = nil
        return result, dropped
    end
    return nil, 1
end

return PackagePaths
