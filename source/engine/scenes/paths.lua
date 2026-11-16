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
    local scheme, relative = rest:match('^(%a+)://(.*)$')
    return scheme, relative, ups
end

-- `roots`: { scene, shared, parent }, where `parent` is the roots of the scene that loaded this one.
function Paths.resolve(path, roots)
    local scheme, relative, ups = Paths.parse(path)
    if not scheme then
        return Paths.normalize(path)
    end
    for _ = 1, ups do
        roots = assert(roots and roots.parent, 'No parent scene for asset path: ' .. path)
    end
    local root = scheme == 'shared' and (roots and roots.shared or 'assets')
        or scheme == 'scene' and roots and roots.scene
    assert(root, 'Unknown or unavailable asset namespace: ' .. scheme)
    return Paths.normalize(root) .. '/' .. Paths.normalize(relative)
end

return Paths
