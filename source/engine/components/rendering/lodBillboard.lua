-- The flat, camera-facing last level of a LODGroup (`billboardImage`): a quad that turns around the
-- vertical axis to face the camera, drawn with an alpha-masked image (a tree or a bush from far).
local Billboard = {}

-- Seconds-free helpers only: the group decides when to build and when to turn it.
local CUTOFF = 0.5

-- Creates the quad as a child of the group and returns it.
function Billboard.create(world, group, image)
    local quad = world:create('Mesh3D', {
        name = group.name .. 'Billboard',
        kind = 'quad',
        doubleSided = true,
        castShadow = false,
        receiveShadow = false,
    }, group)
    world:create('SurfaceAppearance3D', {
        colorMap = image,
        alphaMode = 'Mask',
        alphaCutoff = CUTOFF,
    }, quad)
    return quad
end

-- Width and height of the quad: the given numbers, or from the group radius when 0.
function Billboard.size(width, height, radius, pivot)
    local auto = pivot == 'Center' and 2 * radius or radius
    return width > 0 and width or auto, height > 0 and height or auto
end

-- Sizes the quad and, for a 'Bottom' pivot, lifts it so the group position is its lower edge.
function Billboard.place(quad, width, height, pivot)
    local size, position = quad.size, quad.position
    local lift = pivot == 'Center' and 0 or height / 2
    if size[1] ~= width or size[2] ~= height or position[2] ~= lift then
        quad.size = { width, height, 1 }
        quad.position = { 0, lift, 0 }
    end
end

-- Turns the quad around Y so its front (the side the image reads correctly from) looks at the
-- camera position, whatever the group itself is turned to.
function Billboard.face(quad, group, cx, cz)
    local m = group:getWorldMatrix()
    local toCamera = math.deg(math.atan2(cx - m[4], m[12] - cz))
    local yaw = toCamera + math.deg(math.atan2(m[3], m[1]))
    if quad.rotation[2] ~= yaw then
        quad.rotation = { 0, yaw, 0 }
    end
end

return Billboard
