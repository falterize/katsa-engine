-- Shared GLSL sections keep mesh and sprite shadow sampling identical.
local Source = {}

function Source.read(path)
    local code = assert(katsa.filesystem.read(path), 'Missing shader: ' .. path)
    return (
        code:gsub('// @include ([%w_/%.]+)', function(include)
            return Source.read(include)
        end)
    )
end

return Source
