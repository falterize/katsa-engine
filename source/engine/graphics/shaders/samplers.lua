-- Texture values for `sampler2D` uniforms of user shaders. A node's `uniforms` entry may be:
--   a path or manifest name      loaded through the world's resources (filter_nearest / filter_linear and repeat_enable /
--                                repeat_disable on the uniform pick the sampler)
--   a node with `getTexture()`   e.g. a ViewportFrame: the live canvas it renders into
--   an image or canvas object    sent as is
local Samplers = {}

-- The texture to send for `value`, or nil while there is nothing to show yet (a ViewportFrame
-- that has not drawn). `info` is the parsed uniform (`hints`, `sampler`).
function Samplers.resolve(resources, value, info)
    local kind = type(value)
    if kind == 'string' then
        if value == '' then
            return nil
        end
        local hints = info and info.hints or {}
        local pixel
        if hints.filter_nearest then
            pixel = true
        elseif hints.filter_linear then
            pixel = false
        end
        return resources:imageVariant(value, pixel, hints.repeat_disable and 'clamp' or nil)
    end
    if kind == 'table' and value.getTexture then
        return value:getTexture()
    end
    return value
end

return Samplers
