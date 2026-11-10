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

function Paths.resolve(path, roots)
    local scheme, relative = path:match('^(%a+)://(.*)$')
    if not scheme then
        return Paths.normalize(path)
    end
    local root = scheme == 'shared' and (roots and roots.shared or 'assets')
        or scheme == 'scene' and roots and roots.scene
    assert(root, 'Unknown or unavailable asset namespace: ' .. scheme)
    return Paths.normalize(root) .. '/' .. Paths.normalize(relative)
end

return Paths
