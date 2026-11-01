-- Virtual path normalisation shared by the file system modules.

local Paths = {}

function Paths.normalize(path)
    assert(type(path) == 'string', 'Path must be a string')
    path = path:gsub('\\', '/'):gsub('/+', '/')
    local parts = {}
    for part in path:gmatch('[^/]+') do
        if part == '..' then
            error('Invalid path (parent directory references are not allowed): ' .. path)
        elseif part ~= '.' then
            parts[#parts + 1] = part
        end
    end
    return table.concat(parts, '/')
end

return Paths
