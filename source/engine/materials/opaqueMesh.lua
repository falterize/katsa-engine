-- Shared conservative proof for geometry-only depth and discard-free material paths.
local Opacity = require('source.engine.materials.opacity')

local formats = setmetatable({}, { __mode = 'k' })
local Opaque = {}

function Opaque.eligible(object, renderer)
    if
        not object
        or not object.isA
        or not object:isA('Mesh3D')
        or object._resolvedMaterial
        or object.canvas
        or not Opacity.object(object)
        or (object._effectiveCutoff or object.alphaCutoff or 0) > 0.99
    then
        return false
    end
    local geometry, mesh = object.geometry, object.geometry.mesh
    local world = renderer and renderer.world
    local revision = geometry.revision or 0
    local invalidation = renderer and renderer._renderInvalidationRevision or 0
    local worldInvalidation = world and world._renderInvalidationRevision or 0
    local cached = formats[mesh]
    if
        not cached
        or cached.revision ~= revision
        or cached.invalidation ~= invalidation
        or cached.worldInvalidation ~= worldInvalidation
    then
        -- This also detects attached VertexColor streams, which getVertexFormat omits.
        local ok, value = pcall(mesh.isAttributeEnabled, mesh, 'VertexColor')
        local plain = ok and value == false
            or not ok and tostring(value):find('does not have', 1, true) ~= nil
        cached = {
            revision = revision,
            invalidation = invalidation,
            worldInvalidation = worldInvalidation,
            plain = plain,
        }
        formats[mesh] = cached
    end
    return cached.plain
end

return Opaque
