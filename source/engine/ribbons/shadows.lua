-- Shadow proxies for ribbons: the strip the camera sees becomes one alpha tested caster / receiver in
-- the shared shadow atlas (see graphics/shadows/casterProxy.lua).
local CasterProxy = require('../graphics.shadows.casterProxy')
local Geometry = require('./geometry')
local Image = require('../components.media.image')
local Renderer = require('./renderer')

local S = {}
local bounds = { 0, 0, 0, 0 }

-- Appends one proxy per casting / receiving ribbon to `output` (already holding the world objects).
function S.prepare(world, camera, output)
    if not world.environment.shadows.enabled then
        return output
    end
    local time = world.simulationTime or 0
    for _, node in ipairs(world.ribbons.nodes) do
        if (node.castShadow or node.receiveShadow) and (node._count or 0) >= 2 then
            local proxy = CasterProxy.begin(world, node)
            local image = Image.resolve(world.resources, node, node.texture, world.environment)
            local options = Renderer.options(node, camera, node._shadowOptions)
            node._shadowOptions = options
            Renderer.mapping(node, image, time, options)
            Renderer.applyStatic(node._points, node._count, options)
            local strip = node._shadowStrip or {}
            node._shadowStrip = strip
            local n = Geometry.strip(node._points, node._count, options, strip)
            local peak = 0
            for i = 1, n do
                local v = strip[i]
                CasterProxy.write(proxy, i, v[1], v[2], v[3], v[4], v[5], v[9])
                peak = math.max(peak, v[9])
            end
            -- A ribbon that is entirely more transparent than the cutoff casts nothing.
            local count = peak > node.shadowAlphaCutoff and n or 0
            bounds[1], bounds[2], bounds[3] = node._center[1], node._center[2], node._center[3]
            bounds[4] = node._radius
            CasterProxy.publish(proxy, node, count, image, bounds, output)
        elseif node._shadowProxy then
            CasterProxy.release(node._shadowProxy)
        end
    end
    return output
end

return S
