-- Breaking, placing and picking blocks along the view ray, plus the black selection outline.
local Geometry = require('source.engine.graphics.geometry.primitives')
local Mesh = require('source.engine.composition.mesh')
local Raycast = require('../world.raycast')

local Interaction = {}
Interaction.__index = Interaction

-- Twelve thin bars around a unit cube, slightly larger so they never z-fight the faces.
local function outlineGeometry()
    local vertices = {}
    local lo, hi, t = -0.503, 0.503, 0.012
    local function box(x0, y0, z0, x1, y1, z1)
        local c = {
            { x0, y0, z0 }, { x1, y0, z0 }, { x1, y1, z0 }, { x0, y1, z0 },
            { x0, y0, z1 }, { x1, y0, z1 }, { x1, y1, z1 }, { x0, y1, z1 },
        }
        local quads = {
            { 1, 2, 3, 4, 0, 0, -1 }, { 6, 5, 8, 7, 0, 0, 1 }, { 5, 1, 4, 8, -1, 0, 0 },
            { 2, 6, 7, 3, 1, 0, 0 }, { 4, 3, 7, 8, 0, 1, 0 }, { 5, 6, 2, 1, 0, -1, 0 },
        }
        for _, q in ipairs(quads) do
            local a, b, cc, d = c[q[1]], c[q[2]], c[q[3]], c[q[4]]
            for _, p in ipairs({ a, b, cc, a, cc, d }) do
                vertices[#vertices + 1] = { p[1], p[2], p[3], 0, 0, q[5], q[6], q[7] }
            end
        end
    end
    for _, y in ipairs({ lo, hi - t }) do
        for _, z in ipairs({ lo, hi - t }) do
            box(lo, y, z, hi, y + t, z + t)
        end
    end
    for _, x in ipairs({ lo, hi - t }) do
        for _, z in ipairs({ lo, hi - t }) do
            box(x, lo, z, x + t, hi, z + t)
        end
    end
    for _, x in ipairs({ lo, hi - t }) do
        for _, y in ipairs({ lo, hi - t }) do
            box(x, y, lo, x + t, y + t, hi)
        end
    end
    return Geometry.mesh(vertices)
end

function Interaction.new(scene, world, walker, hotbar, camera, settings)
    local self = setmetatable({
        world = world,
        walker = walker,
        hotbar = hotbar,
        camera = camera,
        reach = settings.reach,
        eye = settings.eyeHeight,
        target = nil,
    }, Interaction)
    self.outline = Mesh.create(scene.world, {
        name = 'Selection',
        geometry = outlineGeometry(),
        color = { 0, 0, 0, 1 },
        visible = false,
    })
    return self
end

-- Looks along the camera ray; called once per frame after the camera moved.
function Interaction:update()
    local pitch, yaw = math.rad(self.camera.rotation[1]), math.rad(self.camera.rotation[2])
    local dx, dy, dz = math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch)
    local w = self.walker
    local hit = Raycast.cast(self.world, w.x, w.y + self.eye, w.z, dx, dy, dz, self.reach)
    self.target = hit
    if hit then
        self.outline.position = { hit.x + 0.5, hit.y + 0.5, hit.z + 0.5 }
    end
    if self.outline.visible ~= (hit ~= nil) then
        self.outline.visible = hit ~= nil
    end
end

function Interaction:breakBlock()
    local hit = self.target
    if hit and self.world:setBlock(hit.x, hit.y, hit.z, 0) then
        self:update()
    end
end

function Interaction:placeBlock()
    local hit = self.target
    if not (hit and hit.px) then
        return
    end
    -- Never entomb the player.
    if self.walker:overlapsBlock(hit.px, hit.py, hit.pz) then
        return
    end
    if self.world:setBlock(hit.px, hit.py, hit.pz, self.hotbar:current()) then
        self:update()
    end
end

-- Middle click: the looked-at block goes into the selected slot.
function Interaction:pickBlock()
    if self.target then
        self.hotbar:set(self.target.id)
    end
end

function Interaction:release()
    if self.outline and not self.outline.destroyed then
        self.outline:destroy()
    end
end

return Interaction
