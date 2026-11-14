-- Shader composer: builds GLSL programs from engine templates plus user shaders.
--
--   local shader = Composer.user('scene://shaders/dissolve.glsl', { canonical = ... })
--   local program = Composer.build('assets/shaders/engine/spatial/main.glsl', {
--       shaders = { shader },
--       defines = { SHADOWS = true },
--       constants = { skinEnabled = false },
--   })
--   katsa.graphics.newShader(program.source)
--
-- Templates are ordinary dialect GLSL with these composer directives:
--   #include "path"                 splice a chunk (relative './x' or a project path)
--   #specialize bool name           `uniform bool name;`, or a `const` when options.constants has it
--   #user_code                     the user shaders' uniforms, helpers and wrapped entry points
--
-- User entry points reach the template through macros the composer defines before `#user_code`
-- is used: KATSA_USER_VERTEX, KATSA_USER_FRAGMENT and KATSA_USER_LIGHT (each only when some
-- shader defines that function), plus KATSA_USER_POSITION, KATSA_USER_ALPHA, KATSA_USER_UNSHADED.
local Tokens = require('./tokens')
local Parser = require('./parser')
local Source = require('./source')
local Builtins = require('./builtins')

local Composer = {}

local function entryMacro(name)
    return 'KATSA_USER_' .. name:upper()
end

local function parameterList(params)
    local parts = {}
    for i, param in ipairs(params) do
        parts[i] = param.qualifier .. ' ' .. param.type .. ' ' .. param.name
    end
    return table.concat(parts, ', ')
end

local function argumentList(params, overrides)
    local parts = {}
    for i, param in ipairs(params) do
        parts[i] = overrides and overrides[param.name] or param.name
    end
    return table.concat(parts, ', ')
end

-- Loads and parses one user shader. `kind` is the shader_type the caller can run.
function Composer.user(path, options)
    options = options or {}
    local lines = Source.load(path, options)
    return Composer.parseLines(lines, path, options.kind)
end

function Composer.parseText(text, label, options)
    options = options or {}
    return Composer.parseLines(Source.fromText(text, label, options), label, options.kind)
end

function Composer.parseLines(lines, label, kind)
    local ok, result = pcall(Parser.parse, Source.join(lines), label)
    if not ok then
        local message = tostring(result)
        local number = message:match('shader line (%d+):')
        local origin = number and lines[tonumber(number)]
        if origin then
            message = message:gsub('^shader line %d+:', origin.file .. ':' .. origin.line .. ':')
        else
            message = label .. ': ' .. message
        end
        error(message, 0)
    end
    local info = result
    info.origin = lines
    info.path = label
    local allowed = Builtins.types[info.type]
    if not allowed then
        error(('%s: unknown shader_type "%s"'):format(label, tostring(info.type)), 0)
    end
    if kind and info.type ~= kind then
        error(('%s: shader_type %s cannot be used here (needs %s)'):format(label, info.type, kind), 0)
    end
    for mode in pairs(info.modes) do
        if not Builtins.modes[info.type][mode] then
            error(('%s: unsupported render_mode "%s" for %s'):format(label, mode, info.type), 0)
        end
    end
    for name in pairs(info.entries) do
        if not allowed[name] then
            error(('%s: %s() is not available in shader_type %s'):format(label, name, info.type), 0)
        end
    end
    return info
end

-- Appends the tokens first..last as lines carrying their user-source origin.
local function emitTokens(out, list, first, last, rename, origin, pending)
    local buffer, bufferLine = pending.text or '', pending.line
    for i = first, last do
        local token = list[i]
        local text = token.text
        if token.kind == 'id' and rename[text] then
            local previous = list[i - 1]
            local k = i - 1
            while previous and not Tokens.significant(previous) do
                k = k - 1
                previous = list[k]
            end
            if not (previous and previous.text == '.') then
                text = rename[text]
            end
        end
        bufferLine = bufferLine or token.line
        local rest = text
        while true do
            local newline = rest:find('\n', 1, true)
            if not newline then
                buffer = buffer .. rest
                break
            end
            buffer = buffer .. rest:sub(1, newline - 1)
            local source = origin[bufferLine]
            out[#out + 1] = {
                text = buffer,
                file = source and source.file or '<user>',
                line = source and source.line or 0,
            }
            buffer, bufferLine = '', (bufferLine or token.line) + 1
            rest = rest:sub(newline + 1)
        end
    end
    pending.text, pending.line = buffer, bufferLine
end

local function flush(out, pending, origin)
    if pending.text and pending.text ~= '' then
        local source = origin[pending.line or 0]
        out[#out + 1] = {
            text = pending.text,
            file = source and source.file or '<user>',
            line = source and source.line or 0,
        }
    end
    pending.text, pending.line = nil, nil
end

local function generated(out, text)
    for line in (text .. '\n'):gmatch('(.-)\n') do
        out[#out + 1] = { text = line, file = '<composer>', line = 0 }
    end
end

local function mentions(info, entry, names)
    local body = info.entries[entry] and info.entries[entry].body
    if not body then
        return false
    end
    for _, token in ipairs(Tokens.scan(body)) do
        if token.kind == 'id' and names[token.text] then
            return true
        end
    end
    return false
end

-- Lines for `#user_code`: every shader's declarations and functions, then the wrappers.
local function emitUser(shaders, kind, want, result)
    local out = {}
    local table_ = Builtins.types[kind]
    local defined, flags = {}, {}
    for index, info in ipairs(shaders) do
        local prefix = 's' .. index .. '_'
        local rename = {}
        for name in pairs(info.names) do
            rename[name] = prefix .. name
        end
        for _, uniform in ipairs(info.uniforms) do
            rename[uniform.name] = prefix .. uniform.name
        end
        for entry in pairs(Parser.entryNames) do
            rename[entry] = prefix .. entry
        end
        generated(out, ('// shader %d: %s'):format(index, info.label))
        local pending = {}
        local list, origin = info.tokens, info.origin
        for _, block in ipairs(info.blocks) do
            if block.kind == 'uniform' then
                local uniform = block.uniform
                emitTokens(out, list, uniform.range[1], uniform.range[2], rename, origin, pending)
                pending.text = (pending.text or ''):gsub('%s+$', '') .. ';'
                flush(out, pending, origin)
                local compiled = prefix .. uniform.name
                result.uniforms[compiled] = { shader = index, name = uniform.name, info = uniform }
                if uniform.default ~= nil then
                    result.defaults[compiled] = uniform.default
                end
            elseif block.kind == 'header' then
                -- shader_type / render_mode never reach GLSL
            elseif block.entry then
                local entry = info.entries[block.entry]
                if want[block.entry] then
                    local params = table_[block.entry]
                    local head = ('void %s%s(%s) {'):format(prefix, block.entry, parameterList(params))
                    pending.text, pending.line = head, list[entry.open].line
                    emitTokens(out, list, entry.open + 1, entry.close - 1, rename, origin, pending)
                    pending.text = (pending.text or '') .. '}'
                    flush(out, pending, origin)
                    defined[block.entry] = defined[block.entry] or {}
                    table.insert(defined[block.entry], index)
                end
            else
                emitTokens(out, list, block.first, block.last, rename, origin, pending)
            end
            if block.kind ~= 'uniform' and block.kind ~= 'space' then
                flush(out, pending, origin)
            end
        end
        flush(out, pending, origin)
        for mode in pairs(info.modes) do
            result.modes[mode] = true
        end
    end
    for _, entry in ipairs({ 'vertex', 'fragment', 'light' }) do
        local users = defined[entry]
        if users then
            local params = table_[entry]
            local wrapper = 'katsa_user' .. entry:sub(1, 1):upper() .. entry:sub(2)
            generated(out, ('void %s(%s) {'):format(wrapper, parameterList(params)))
            for _, index in ipairs(users) do
                local info = shaders[index]
                local overrides
                if entry == 'vertex' and kind == 'spatial' then
                    if mentions(info, 'vertex', { POSITION = true }) then
                        flags.KATSA_USER_POSITION = true
                    else
                        overrides = { POSITION = 'katsa_unusedPosition' }
                    end
                end
                if overrides then
                    generated(out, '    highp vec4 katsa_unusedPosition;')
                end
                generated(out, ('    s%d_%s(%s);'):format(index, entry, argumentList(params, overrides)))
                if entry == 'fragment' and mentions(info, 'fragment', { ALPHA = true, discard = true }) then
                    flags.KATSA_USER_ALPHA = true
                end
            end
            generated(out, '}')
            flags[entryMacro(entry)] = wrapper .. '(' .. argumentList(params) .. ')'
        end
    end
    if result.modes.unshaded then
        flags.KATSA_USER_UNSHADED = true
    end
    return out, flags
end

local function defineLine(name, value)
    if value == true then
        return '#define ' .. name .. ' 1'
    end
    return '#define ' .. name .. ' ' .. tostring(value)
end

local function constantLine(kind, name, value)
    return ('const %s %s = %s;'):format(kind, name, tostring(value))
end

-- options.shaders    list of parsed user shaders (Composer.user)
-- options.kind       their shader_type (default 'spatial')
-- options.entries    set of entry points this program runs (default vertex, fragment, light)
-- options.defines    { NAME = true | number | string } emitted as #define
-- options.constants  { name = value } turns `#specialize` uniforms into constants
-- options.read, options.canonical  file access (see Source)
-- Returns { source, map, uniforms, defaults, modes, flags }.
function Composer.build(template, options)
    options = options or {}
    local kind = options.kind or 'spatial'
    local want = options.entries or { vertex = true, fragment = true, light = true }
    local shaders = options.shaders or {}
    local result = { uniforms = {}, defaults = {}, modes = {}, template = template }
    local lines = {}
    generated(lines, '#pragma language glsl3')
    local names = {}
    for name in pairs(options.defines or {}) do
        names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local value = options.defines[name]
        if value ~= false then
            generated(lines, defineLine(name, value))
        end
    end
    local userLines, flags = emitUser(shaders, kind, want, result)
    local flagNames = {}
    for name in pairs(flags) do
        flagNames[#flagNames + 1] = name
    end
    table.sort(flagNames)
    for _, name in ipairs(flagNames) do
        local value = flags[name]
        generated(lines, value == true and defineLine(name, true) or ('#define %s %s'):format(name, value))
    end
    local body = Source.load(template, options)
    local used = false
    for _, line in ipairs(body) do
        local text = line.text
        local specialType, specialName = text:match('^%s*#%s*specialize%s+(%w+)%s+([%w_]+)%s*$')
        if specialType then
            local constant = options.constants and options.constants[specialName]
            local replaced = constant ~= nil and constantLine(specialType, specialName, constant)
                or ('uniform %s %s;'):format(specialType, specialName)
            lines[#lines + 1] = { text = replaced, file = line.file, line = line.line }
        elseif text:match('^%s*#%s*user_code%s*$') then
            assert(not used, template .. ': #user_code appears twice')
            used = true
            for _, userLine in ipairs(userLines) do
                lines[#lines + 1] = userLine
            end
        else
            lines[#lines + 1] = line
        end
    end
    result.map = lines
    result.source = Source.join(lines)
    result.flags = flags
    return result
end

-- Compiles a program through `compile(source)`; a failure is reported against the authored
-- files instead of the composed text.
function Composer.explain(program, message)
    message = tostring(message)
    local function trace(number)
        local origin = program.map[tonumber(number)]
        if origin and origin.file ~= '<composer>' then
            return origin.file .. ':' .. origin.line
        end
        return nil
    end
    local mapped = message:gsub('%f[%d]0:(%d+)', function(number)
        return trace(number) or ('0:' .. number)
    end)
    mapped = mapped:gsub('%f[%d]0%((%d+)%)', function(number)
        return trace(number) or ('0(' .. number .. ')')
    end)
    return mapped
end

return Composer
