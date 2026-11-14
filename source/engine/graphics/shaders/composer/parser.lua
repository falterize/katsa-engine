-- Reads a user shader written in the Godot-style structure:
--
--   shader_type spatial;
--   render_mode unshaded;
--   uniform float amount : hint_range(0.0, 1.0) = 0.5;
--   varying vec3 local;
--   void vertex() { ... }
--   void fragment() { ... }
--
-- The parser does not understand GLSL expressions. It splits the file at top level into
-- declarations and functions, which is all the composer needs to rename, wrap and report.
local Tokens = require('./tokens')

local Parser = {}

local entryNames = { vertex = true, fragment = true, light = true }
local samplerTypes = {
    sampler2D = 'image',
    Image = 'image',
    sampler3D = 'volume',
    VolumeImage = 'volume',
    samplerCube = 'cube',
    CubeImage = 'cube',
    sampler2DArray = 'array',
    ArrayImage = 'array',
}
local componentCount = {
    float = 1, int = 1, uint = 1, bool = 1,
    vec2 = 2, vec3 = 3, vec4 = 4,
    ivec2 = 2, ivec3 = 3, ivec4 = 4,
    bvec2 = 2, bvec3 = 3, bvec4 = 4,
}

local function fail(message, token)
    error(('shader line %d: %s'):format(token and token.line or 0, message), 0)
end

-- Evaluates a uniform default such as `1.0`, `-2`, `true` or `vec3(0.2, 0.4, 0.6)`.
local function evaluate(tokens, kind)
    local numbers = {}
    local text = Tokens.join(tokens):gsub('%s+', '')
    if text == 'true' or text == 'false' then
        return text == 'true'
    end
    local inner = text:match('^[%w]+%((.*)%)$') or text
    for part in inner:gmatch('[^,]+') do
        local value = tonumber((part:gsub('[fFuU]$', '')))
        if value == nil then
            fail('uniform default must be a number or a constructor of numbers: ' .. text, tokens[1])
        end
        numbers[#numbers + 1] = value
    end
    local count = componentCount[kind]
    if not count then
        fail('uniform default is not supported for type ' .. tostring(kind), tokens[1])
    end
    if count == 1 then
        return numbers[1]
    end
    if #numbers == 1 then
        for i = 2, count do
            numbers[i] = numbers[1]
        end
    end
    if #numbers ~= count then
        fail(('uniform default needs %d components, got %d'):format(count, #numbers), tokens[1])
    end
    return numbers
end

-- Parses the hint list after ':' (`source_color, hint_range(0, 1)`).
local function hints(tokens)
    local result = {}
    local i, count = 1, #tokens
    while i <= count do
        local token = tokens[i]
        if token.kind == 'id' then
            local name = token.text
            local nextToken = tokens[i + 1]
            if nextToken and nextToken.text == '(' then
                local close = Tokens.matching(tokens, i + 1)
                local values = {}
                for part in Tokens.join(tokens, i + 2, close - 1):gmatch('[^,]+') do
                    -- Numbers for hint_range; quoted names for hint_enum("A", "B").
                    values[#values + 1] = tonumber(part)
                        or part:gsub('^%s+', ''):gsub('%s+$', ''):gsub('^"(.*)"$', '%1')
                end
                result[name] = values
                i = close
            else
                result[name] = true
            end
        end
        i = i + 1
    end
    return result
end

-- A uniform declaration: [precision] type name[array] [: hints] [= default];
local function uniform(tokens, first, last)
    local words, hintStart, defaultStart = {}, nil, nil
    local depth = 0
    for i = first, last do
        local token = tokens[i]
        if token.kind == 'op' then
            if token.text == '(' or token.text == '[' then
                depth = depth + 1
            elseif token.text == ')' or token.text == ']' then
                depth = depth - 1
            elseif depth == 0 and token.text == ':' and not hintStart and not defaultStart then
                hintStart = i
            elseif depth == 0 and token.text == '=' and not defaultStart then
                defaultStart = i
            end
        end
    end
    local declarationEnd = (hintStart or defaultStart or last + 1) - 1
    local ids = {}
    for i = first, declarationEnd do
        if tokens[i].kind == 'id' then
            ids[#ids + 1] = tokens[i]
        end
    end
    -- ids[1] is `uniform`; the last id is the name, the one before it is the type.
    if #ids < 3 then
        fail('malformed uniform declaration', tokens[first])
    end
    local name, kind = ids[#ids].text, ids[#ids - 1].text
    local info = {
        name = name,
        type = kind,
        sampler = samplerTypes[kind],
        hints = hintStart and hints({ unpack(tokens, hintStart + 1, (defaultStart or last + 1) - 1) })
            or {},
    }
    if defaultStart then
        info.default = evaluate({ unpack(tokens, defaultStart + 1, last) }, kind)
    end
    local arrayAfterName = tokens[declarationEnd] and tokens[declarationEnd].text == ']'
    info.array = arrayAfterName or nil
    -- GLSL ES forbids uniform initializers, and hints are not GLSL: only the bare declaration
    -- (tokens first..last) is emitted.
    info.range = { first, declarationEnd }
    return info
end

-- Splits `source` (already include-expanded) into the pieces the composer assembles.
-- Returns {
--   type, modes = { name = true }, uniforms = {...}, entries = { vertex = {body, line}, ... },
--   code = 'everything else, in source order' (helpers, constants, varyings, structs),
--   names = { global identifiers declared by the shader }
-- }
function Parser.parse(source, label)
    local list = Tokens.scan(source)
    local info = {
        label = label,
        modes = {},
        uniforms = {},
        entries = {},
        names = {},
        blocks = {},
    }
    local count = #list
    local i = 1
    local function nextSignificant(index)
        while index <= count and not Tokens.significant(list[index]) do
            index = index + 1
        end
        return index
    end
    local function declare(name)
        if name and not info.names[name] then
            info.names[name] = true
        end
    end
    while i <= count do
        local token = list[i]
        if not Tokens.significant(token) then
            info.blocks[#info.blocks + 1] = { first = i, last = i, kind = 'space' }
            i = i + 1
        elseif token.kind == 'directive' then
            info.blocks[#info.blocks + 1] = { first = i, last = i, kind = 'directive' }
            i = i + 1
        else
            -- One top-level item: runs to ';' at depth 0, or through the closing '}' of a function.
            local start, depth, parens = i, 0, 0
            local finish, isFunction, braceOpen
            local isStruct = list[i].text == 'struct'
            local j = i
            while j <= count do
                local current = list[j]
                if current.kind == 'op' then
                    local text = current.text
                    if text == '(' then
                        parens = parens + 1
                    elseif text == ')' then
                        parens = parens - 1
                    elseif text == '{' and parens == 0 then
                        braceOpen = braceOpen or j
                        depth = depth + 1
                    elseif text == '}' and parens == 0 then
                        depth = depth - 1
                        if depth == 0 and not isStruct then
                            isFunction = true
                            finish = j
                            break
                        end
                    elseif text == ';' and parens == 0 and depth == 0 then
                        finish = j
                        break
                    end
                end
                j = j + 1
            end
            if not finish then
                fail('unterminated declaration', token)
            end
            local first = nextSignificant(start)
            local firstWord = list[first].text
            local block = { first = start, last = finish }
            if isFunction then
                local open = braceOpen
                -- `type name(params) {`: the name is the identifier before the first '('.
                local nameIndex
                for k = start, open do
                    if list[k].text == '(' then
                        for m = k - 1, start, -1 do
                            if list[m].kind == 'id' then
                                nameIndex = m
                                break
                            end
                        end
                        break
                    end
                end
                local name = nameIndex and list[nameIndex].text
                local close = Tokens.matching(list, open)
                block.kind = 'function'
                block.name = name
                block.open, block.close = open, close
                if entryNames[name] then
                    if info.entries[name] then
                        fail('function ' .. name .. '() is defined twice', list[nameIndex])
                    end
                    info.entries[name] = {
                        line = list[open].line,
                        open = open,
                        close = close,
                        body = Tokens.join(list, open + 1, close - 1),
                        first = start,
                        last = finish,
                    }
                    block.entry = name
                else
                    declare(name)
                end
            elseif firstWord == 'shader_type' then
                local kind = list[nextSignificant(first + 1)]
                info.type = kind.text
                block.kind = 'header'
            elseif firstWord == 'render_mode' then
                for k = first + 1, finish - 1 do
                    if list[k].kind == 'id' then
                        info.modes[list[k].text] = true
                    end
                end
                block.kind = 'header'
            elseif firstWord == 'uniform' then
                local entry = uniform(list, first, finish - 1)
                entry.line = list[first].line
                info.uniforms[#info.uniforms + 1] = entry
                declare(entry.name)
                block.kind = 'uniform'
                block.uniform = entry
            else
                block.kind = 'code'
                if firstWord == 'struct' then
                    declare(list[nextSignificant(first + 1)].text)
                else
                    -- `const float k = 1.0;`, `varying vec3 p;`, `float x;`: the name is the last
                    -- identifier before '=', '[' or ';' at depth 0.
                    local lastId
                    local nest = 0
                    for k = first, finish - 1 do
                        local current = list[k]
                        if current.text == '(' or current.text == '[' then
                            nest = nest + 1
                        elseif current.text == ')' or current.text == ']' then
                            nest = nest - 1
                        elseif nest == 0 and current.text == '=' then
                            break
                        elseif nest == 0 and current.kind == 'id' then
                            lastId = current.text
                        end
                    end
                    declare(lastId)
                end
            end
            info.blocks[#info.blocks + 1] = block
            i = finish + 1
        end
    end
    info.tokens = list
    if not info.type then
        fail('missing `shader_type`')
    end
    return info
end

Parser.entryNames = entryNames

return Parser
