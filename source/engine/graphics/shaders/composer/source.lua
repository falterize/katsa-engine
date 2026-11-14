-- Reads shader files and expands `#include "path"` directives.
--
-- Output is a list of lines, each remembering the file and line it came from, so a compile
-- error reported against the composed text can be traced back to the authored file.
local Source = {}

local MAX_DEPTH = 16

local function directory(path)
    return path:match('^(.*)/[^/]*$') or ''
end

-- './x' and '../x' are relative to the including file; anything else is a project path
-- ('assets/...', 'scene://...', 'shared://...').
local function resolve(path, from, canonical)
    if path:sub(1, 2) == './' or path:sub(1, 3) == '../' then
        local parts = {}
        local base = directory(from)
        for part in (base .. '/' .. path):gmatch('[^/]+') do
            if part == '..' then
                parts[#parts] = nil
            elseif part ~= '.' then
                parts[#parts + 1] = part
            end
        end
        return table.concat(parts, '/')
    end
    return canonical and canonical(path) or path
end

local function expand(lines, path, text, options, stack)
    assert(#stack < MAX_DEPTH, 'Shader includes are nested too deeply: ' .. path)
    for _, active in ipairs(stack) do
        assert(active ~= path, 'Shader include cycle through ' .. path)
    end
    stack[#stack + 1] = path
    local number = 0
    for line in (text .. '\n'):gmatch('(.-)\r?\n') do
        number = number + 1
        local include = line:match('^%s*#%s*include%s+"([^"]+)"%s*$')
        if include then
            local target = resolve(include, path, options.canonical)
            local content = options.read(target)
            assert(content, ('%s:%d: cannot include "%s"'):format(path, number, include))
            expand(lines, target, content, options, stack)
        else
            lines[#lines + 1] = { text = line, file = path, line = number }
        end
    end
    stack[#stack] = nil
end

-- options.read(path) -> text or nil (default: katsa.filesystem.read)
-- options.canonical(path) -> project path (default: identity)
function Source.load(path, options)
    options = options or {}
    local settings = {
        read = options.read or function(target)
            return katsa.filesystem.read(target)
        end,
        canonical = options.canonical,
    }
    local text = settings.read(path)
    assert(text, 'Missing shader: ' .. path)
    local lines = {}
    expand(lines, path, text, settings, {})
    return lines
end

function Source.fromText(text, label, options)
    local lines = {}
    local settings = {
        read = options and options.read or function(target)
            return katsa.filesystem.read(target)
        end,
        canonical = options and options.canonical,
    }
    expand(lines, label or '<shader>', text, settings, {})
    return lines
end

function Source.join(lines)
    local parts = {}
    for i, line in ipairs(lines) do
        parts[i] = line.text
    end
    return table.concat(parts, '\n')
end

return Source
