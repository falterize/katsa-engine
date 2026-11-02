-- Relative module names: `require('./sibling')` is a module in the caller's folder,
-- `require('../other.module')` one folder up, `require('../../x')` two up. The rest after the
-- leading `./` / `../` parts is an ordinary dotted name (`./nodes.navMap` is nodes/navMap.lua).
-- Moving a folder then keeps every require inside it valid.
--
-- The caller is found from its chunk name, so a relative require must not be a tail call:
-- write `return (require('./part'))`, not `return require('./part')`.
local Relative = {}

function Relative.isRelative(name)
    return type(name) == 'string' and (name:sub(1, 2) == './' or name:sub(1, 3) == '../')
end

-- Folder of a file path ('a/b/c.lua' -> 'a/b'; 'c.lua' -> '').
local function folderOf(path)
    return (path:gsub('\\', '/'):match('^(.*)/[^/]*$')) or ''
end

-- Resolves `name` against the file `path` (relative to the root the result is relative to).
-- Returns the absolute dotted module name.
function Relative.resolve(name, path)
    local folder = folderOf(path)
    local rest = name
    while true do
        if rest:sub(1, 2) == './' then
            rest = rest:sub(3)
        elseif rest:sub(1, 3) == '../' then
            assert(folder ~= '', 'Relative require leaves the module root: ' .. name)
            folder = folderOf(folder)
            rest = rest:sub(4)
        else
            break
        end
    end
    assert(rest ~= '' and not rest:find('/', 1, true), 'Invalid relative require: ' .. name)
    return folder == '' and rest or (folder:gsub('/', '.') .. '.' .. rest)
end

-- The file the function `level` frames above the caller of this function runs in.
function Relative.callerPath(level)
    local info = debug.getinfo((level or 1) + 1, 'S')
    local source = info and info.source
    assert(
        source and source:sub(1, 1) == '@',
        'A relative require needs a calling file (do not tail-call require)'
    )
    return source:sub(2)
end

-- Returns a require that also understands relative names; other names go to `base`.
function Relative.wrap(base)
    return function(name, ...)
        if Relative.isRelative(name) then
            name = Relative.resolve(name, Relative.callerPath(2))
        end
        return base(name, ...)
    end
end

return Relative
