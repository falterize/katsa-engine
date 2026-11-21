local Paths = {}

function Paths.normalize(path)
    assert(type(path) == 'string' and path ~= '', 'Asset path must be a non-empty string')
    assert(not path:match('^[/\\]') and not path:match('^%a:'), 'Asset path must be relative')
    local parts = {}
    for part in path:gsub('\\', '/'):gmatch('[^/]+') do
        if part == '..' then
            assert(#parts > 0, 'Asset path escapes its root')
            parts[#parts] = nil
        elseif part ~= '.' then
            parts[#parts + 1] = part
        end
    end
    assert(#parts > 0, 'Asset path must name a file or directory')
    return table.concat(parts, '/')
end

-- The last segment of a path ('a/b/scene' -> 'scene').
function Paths.basename(path)
    return (path:gsub('\\', '/'):match('([^/]+)/*$')) or path
end

-- Splits 'scene://x', './scene://x' or '../scene://x' (any mix of './' and '../', like a Lua module
-- path) into scheme, relative path and how many scenes up it points: a prefab's `../scene://x` is
-- an asset of the scene that loaded it.
function Paths.parse(path)
    local ups, rest = 0, path
    while true do
        local tail = rest:match('^%./(.*)$')
        if not tail then
            tail = rest:match('^%.%./(.*)$')
            if not tail then
                break
            end
            ups = ups + 1
        end
        rest = tail
    end
    local scheme, relative = rest:match('^([%a_][%w_%-]*)://(.*)$')
    return scheme, relative, ups
end

-- The root of a scheme a scene registered by name (`roots.named`, see Paths.name); the scenes that
-- loaded this one are searched too.
local function named(roots, scheme)
    while roots do
        local root = roots.named and roots.named[scheme]
        if root then
            return root
        end
        roots = roots.parent
    end
end

-- Registers `scheme://x` as an asset of the scene rooted at `root` in `roots` (a loaded prefab).
-- A name the caller chose (`strict`) must be valid, not reserved (`scene`, `shared`) and free; a
-- default name (the scene id) is only registered when it can be: the first scene with an id gets it.
function Paths.name(roots, scheme, root, strict)
    local problem = not scheme:match('^[%a_][%w_%-]*$') and 'is not a valid name'
        or (scheme == 'scene' or scheme == 'shared') and 'is reserved'
    roots.named = roots.named or {}
    local existing = roots.named[scheme]
    problem = problem or existing and existing ~= root and 'is already used by another scene'
    if problem then
        assert(not strict, 'Scene name "' .. tostring(scheme) .. '" ' .. problem)
        return false
    end
    roots.named[scheme] = root
    return true
end

-- `shared://` answers to one folder or to a list of them (engine assets first, then the folders a
-- project or scene declared): the first root that holds the file wins; a missing file resolves
-- against the first root so the loader reports a normal "file not found".
local function sharedPath(shared, relative)
    if type(shared) ~= 'table' then
        return Paths.normalize(shared or 'assets') .. '/' .. relative
    end
    local first
    for _, root in ipairs(shared) do
        local candidate = Paths.normalize(root) .. '/' .. relative
        first = first or candidate
        if katsa.filesystem.getInfo(candidate) then
            return candidate
        end
    end
    return first or ('assets/' .. relative)
end

-- `roots`: { scene, shared, parent, named }, where `parent` is the roots of the scene that loaded
-- this one and `shared` is a folder or a list of folders.
function Paths.resolve(path, roots)
    local scheme, relative, ups = Paths.parse(path)
    if not scheme then
        return Paths.normalize(path)
    end
    for _ = 1, ups do
        roots = assert(roots and roots.parent, 'No parent scene for asset path: ' .. path)
    end
    if scheme == 'shared' then
        return sharedPath(roots and roots.shared, Paths.normalize(relative))
    end
    local root = scheme == 'scene' and roots and roots.scene
        or named(roots, scheme)
    assert(root, 'Unknown or unavailable asset namespace: ' .. scheme)
    return Paths.normalize(root) .. '/' .. Paths.normalize(relative)
end

return Paths
