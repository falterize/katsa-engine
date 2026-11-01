local ipairs = require('source.engine.math.array').ipairs
-- Source-level rejection is independent of the main camera and its visible list.
local Math = require('source.engine.math.math3d')
local bit = require('bit')

local Casters = {}

function Casters.collect(world, light, layers, localLight, out)
    out = out or {}
    local count, tests = 0, 0
    local lightLayers = light.shadowLayers or -1
    for _, object in ipairs(world._shadowObjects or world.objects) do
        tests = tests + 1
        local radius = object.radius
            + (object.shadowBoundsPadding or 0)
            + (object._shaderBoundsPadding or 0)
            + (localLight and light.range or 0)
        if
            object:isVisible()
            and object.castShadow ~= false
            and not object.onTop
            and (object._renderOpacity or object:getEffectiveOpacity()) > 0
            and bit.band(object.shadowLayers or object.layers or 1, layers, lightLayers or -1) ~= 0
            and world.layerGroups:interacts(
                object.shadowGroup or 'Default',
                light.shadowGroup or 'Default'
            )
            and (
                not localLight
                or object._shaderBoundsUnknown
                or Math.distanceSquared(object.worldPosition, light.worldPosition)
                    <= radius * radius
            )
        then
            count = count + 1
            out[count] = object
        end
    end
    for i = #out, count + 1, -1 do
        out[i] = nil
    end
    return out, tests
end

return Casters
