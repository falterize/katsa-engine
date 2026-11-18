-- Deterministic Lua table text writer: `return { ... }` with sorted keys, so exporting the same
-- location twice gives identical bytes. Accepts numbers, strings, booleans and nested tables
-- (no functions, no cycles, no non-finite numbers); anything else is an error with its path.
local LuaText = {}

local format, concat = string.format, table.concat

local KEYWORDS = {}
for word in
    ('and break do else elseif end false for function goto if in local nil not or repeat return then true until while'):gmatch(
        '%a+'
    )
do
    KEYWORDS[word] = true
end

local function number(value, path)
    if value ~= value or value == math.huge or value == -math.huge then
        error('Cannot write a non-finite number at ' .. path, 0)
    end
    if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
        return format('%d', value)
    end
    return format('%.17g', value)
end

local function isArray(value)
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count == #value, count
end

local function keyText(key, path)
    if type(key) == 'string' and key:match('^[%a_][%w_]*$') and not KEYWORDS[key] then
        return key
    elseif type(key) == 'string' then
        return format('[%q]', key)
    elseif type(key) == 'number' then
        return '[' .. number(key, path) .. ']'
    end
    error('Unsupported table key type ' .. type(key) .. ' at ' .. path, 0)
end

local function write(value, out, indent, path, seen)
    local kind = type(value)
    if kind == 'number' then
        out[#out + 1] = number(value, path)
    elseif kind == 'string' then
        out[#out + 1] = format('%q', value):gsub('\\\n', '\\n')
    elseif kind == 'boolean' then
        out[#out + 1] = tostring(value)
    elseif kind == 'table' then
        assert(not seen[value], 'Cycle in table at ' .. path)
        seen[value] = true
        local array, count = isArray(value)
        if count == 0 then
            out[#out + 1] = '{}'
        elseif array and #value <= 4 and type(value[1]) == 'number' then
            local items = {}
            for index, item in ipairs(value) do
                items[index] = number(item, path)
            end
            out[#out + 1] = '{ ' .. concat(items, ', ') .. ' }'
        else
            local inner = indent .. '    '
            out[#out + 1] = '{\n'
            if array then
                for index, item in ipairs(value) do
                    out[#out + 1] = inner
                    write(item, out, inner, path .. '[' .. index .. ']', seen)
                    out[#out + 1] = ',\n'
                end
            else
                local keys = {}
                for key in pairs(value) do
                    keys[#keys + 1] = key
                end
                table.sort(keys, function(a, b)
                    if type(a) == type(b) then
                        return a < b
                    end
                    return type(a) == 'number'
                end)
                for _, key in ipairs(keys) do
                    out[#out + 1] = inner .. keyText(key, path) .. ' = '
                    write(value[key], out, inner, path .. '.' .. tostring(key), seen)
                    out[#out + 1] = ',\n'
                end
            end
            out[#out + 1] = indent .. '}'
        end
        seen[value] = nil
    else
        error('Cannot write a ' .. kind .. ' value at ' .. path, 0)
    end
end

-- Returns `return <value>\n` as text.
function LuaText.serialize(value)
    local out = { 'return ' }
    write(value, out, '', 'value', {})
    out[#out + 1] = '\n'
    return concat(out)
end

-- Reads text back with an empty environment: a location file can hold data, never code.
function LuaText.parse(text, label)
    local name = '=' .. (label or 'location')
    local chunk, message
    if setfenv then
        chunk, message = loadstring(text, name)
        if chunk then
            setfenv(chunk, {})
        end
    else
        chunk, message = load(text, name, 't', {})
    end
    if not chunk then
        return nil, message
    end
    local ok, result = pcall(chunk)
    if not ok then
        return nil, result
    end
    return result
end

return LuaText
