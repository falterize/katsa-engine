-- Light visualisation as in current editors: every light gets a small icon (a bulb, or a sun for
-- the directional light) of constant size on screen, tinted with the light colour; spot lights and
-- the sun also show a short direction line. The selected light additionally shows its reach: three
-- thin range circles for a point light, the cone for a spot light, an arrow with a ring for the
-- sun. A click on the icon selects the light (an invisible pick sphere carries the click). Everything is drawn on top of the scene (onTop shader) and
-- lives outside the level, so it is never saved, copied or undone. The shapes are built in world
-- space from the engine's own spot direction formula (graphics/debug/gizmos.lua) and rebuilt only
-- when range, radius, rotation or colour change.
local Assign = require('../core.assign')
local Builder = require('./meshBuilder')
local Geometry = require('source.engine.graphics.geometry.primitives')

local ICON_PIXELS = 14 -- on-screen half size of the light icon

local LightViz = {}
LightViz.__index = LightViz

local TYPES = { PointLight3D = true, SpotLight3D = true, DirectionalLight3D = true }
local HALF = 0.01 -- half width of the thin reach lines (world units)
local MARK = 0.008 -- half width of the direction line (drawn at the icon's scale)
local Icons = require('../ui.widgets.icons')

function LightViz.isLight(node)
    return node ~= nil and TYPES[node.className] == true
end

function LightViz.new(world, level)
    return setmetatable({ world = world, level = level, entries = {}, owners = {}, enabled = true, count = 0 }, LightViz)
end

local function tint(light)
    local c = light.color or { 1, 1, 1 }
    local scale = (c[1] > 1 or c[2] > 1 or c[3] > 1) and 255 or 1
    return { c[1] / scale, c[2] / scale, c[3] / scale, 1 }
end

-- Forward, right and up directions of a spot or sun from the node's Euler rotation.
local function basis(rotation)
    local pitch, yaw, roll = math.rad(rotation[1]), math.rad(rotation[2]), math.rad(rotation[3])
    local x, y, z = -math.sin(yaw) * math.cos(pitch), -math.sin(pitch), math.cos(yaw) * math.cos(pitch)
    local dx, dy, dz = x * math.cos(roll) - y * math.sin(roll), y * math.cos(roll) + x * math.sin(roll), z
    local rx, ry, rz = math.cos(yaw) * math.cos(roll), math.cos(yaw) * math.sin(roll), math.sin(yaw)
    local ux, uy, uz = dy * rz - dz * ry, dz * rx - dx * rz, dx * ry - dy * rx
    return { dx, dy, dz }, { rx, ry, rz }, { ux, uy, uz }
end

local function add(a, b, s)
    return { a[1] + b[1] * s, a[2] + b[2] * s, a[3] + b[3] * s }
end

-- A circle of bars around `center` in the plane spanned by unit vectors u and v.
local function circle(vertices, center, u, v, radius, segments, hint)
    local function at(angle)
        return add(add(center, u, math.cos(angle) * radius), v, math.sin(angle) * radius)
    end
    for step = 0, segments - 1 do
        Builder.bar(vertices, at(step / segments * 2 * math.pi), at((step + 1) / segments * 2 * math.pi), hint, HALF)
    end
end

local AXES = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }

-- A short direction line for spots and the sun, in icon space (scaled with the icon).
local function markerVertices(light)
    local vertices, origin = {}, { 0, 0, 0 }
    if light.className ~= 'PointLight3D' then
        local d, r = basis(light.rotation or { 0, 0, 0 })
        local tip = add(origin, d, 1.1)
        Builder.bar(vertices, add(origin, d, 0.35), tip, r, MARK)
        Builder.bar(vertices, tip, add(add(origin, d, 0.85), r, 0.18), d, MARK)
        Builder.bar(vertices, tip, add(add(origin, d, 0.85), r, -0.18), d, MARK)
    end
    return vertices
end

local function reachVertices(light, selected)
    local vertices, origin = {}, { 0, 0, 0 }
    local range = light.range or 10
    if light.className == 'PointLight3D' then
        -- How far the light reaches, and a small ring for its size when it has one.
        for axis = 1, 3 do
            Builder.ring(vertices, axis, range, HALF, 64)
        end
        if (light.radius or 0) > 0.05 then
            for axis = 1, 3 do
                Builder.ring(vertices, axis, light.radius, HALF, 24)
            end
        end
    elseif light.className == 'SpotLight3D' then
        local d, r, u = basis(light.rotation or { 0, 0, 0 })
        local radius = light.radius or 2
        local far = add(origin, d, range)
        circle(vertices, far, r, u, radius, 32, d)
        for i = 0, 3 do
            local a = i * math.pi / 2
            Builder.bar(vertices, origin, add(add(far, r, math.cos(a) * radius), u, math.sin(a) * radius), d, HALF)
        end
        Builder.bar(vertices, origin, far, r, HALF)
    else
        local d, r, u = basis(light.rotation or { 0, 0, 0 })
        Builder.bar(vertices, origin, add(origin, d, 3), r, HALF)
        local tip = add(origin, d, 3)
        for _, side in ipairs({ r, u }) do
            Builder.bar(vertices, tip, add(add(origin, d, 2.6), side, 0.18), d, HALF)
            Builder.bar(vertices, tip, add(add(origin, d, 2.6), side, -0.18), d, HALF)
        end
        circle(vertices, add(origin, d, 1.5), r, u, 0.6, 24, d)
    end
    return vertices
end

function LightViz:create(light)
    self.count = self.count + 1
    local world = self.world
    local entry = { light = light, id = self.count }
    entry.root = world:create('Node3D', { name = 'EditorLightViz' .. entry.id, visible = false })
    world:create('Shader3D', { name = 'OnTop', shaderPath = 'editor://shaders/onTop.glsl' }, entry.root)
    -- The pick sphere: small, solid, tinted; a click on it selects the light.
    entry.pick = world:create('Mesh3D', {
        name = 'EditorLightPick' .. entry.id,
        kind = 'sphere',
        size = { 0.28, 0.28, 0.28 },
        transparency = 0.995, -- picking skips fully transparent meshes, so it is almost, not fully, clear
        lightInfluence = 0,
        castShadow = false,
        canQuery = true,
    }, entry.root)
    self.owners[entry.pick] = light
    -- The icon: a screen-sized billboard (pixels, not metres) drawn over the scene.
    entry.icon = world:create('BillboardUI', {
        name = 'EditorLightIcon' .. entry.id,
        sizeMode = 'Screen',
        size = { 0, ICON_PIXELS * 2, 0, ICON_PIXELS * 2 },
        canvasSize = { ICON_PIXELS * 2, ICON_PIXELS * 2 },
        onTop = true,
        interactable = false,
    }, entry.root)
    entry.image = entry.icon.ui:create('ImageRect', {
        size = { 1, 0, 1, 0 },
        image = Icons.image(light.className == 'DirectionalLight3D' and 'sun' or 'light'),
        fitMode = 'Fit',
        pixelate = true,
        backgroundTransparency = 1,
        interactable = false,
    }, entry.icon.ui.content)
    return entry
end

local function rebuild(self, entry, key, build, field, name)
    if entry[field .. 'Key'] == key then
        return
    end
    entry[field .. 'Key'] = key
    entry.unit = nil -- new geometry: rescale on the next pass
    if entry[field] and not entry[field].destroyed then
        entry[field]:destroy()
    end
    entry[field] = nil
    local vertices = build()
    if #vertices > 0 then
        entry[field] = self.world:create('Mesh3D', {
            name = name .. entry.id,
            geometry = Geometry.mesh(vertices),
            lightInfluence = 0,
            canQuery = false,
            castShadow = false,
        }, entry.root)
    end
end

function LightViz:destroyEntry(entry)
    self.owners[entry.pick] = nil
    if not entry.root.destroyed then
        entry.root:destroy()
    end
end

local function collect(node, out)
    for _, child in ipairs(node.children) do
        if TYPES[child.className] then
            out[#out + 1] = child
        end
        collect(child, out)
    end
end

-- Called every frame. `selection` is the editor selection; `show` hides every marker.
function LightViz:update(selection, show, camera)
    local lights, alive = {}, {}
    if show and self.enabled then
        collect(self.level, lights)
    end
    for _, light in ipairs(lights) do
        alive[light] = true
        local entry = self.entries[light]
        if not entry then
            entry = self:create(light)
            self.entries[light] = entry
        end
        -- worldPosition is an empty cache until the renderer has seen the light.
        local p = light.worldPosition
        if not (p and p[3]) then
            p = light.position
        end
        Assign.vec(entry.root, 'position', p[1], p[2], p[3])
        local color = tint(light)
        local rotation = light.rotation or { 0, 0, 0 }
        local base = ('%s|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f'):format(
            light.className, rotation[1], rotation[2], rotation[3], light.range or 0, light.radius or 0, 0)
        if entry.color ~= color[1] + color[2] * 7 + color[3] * 13 then
            entry.color = color[1] + color[2] * 7 + color[3] * 13
            entry.image.imageColor = { color[1], color[2], color[3] }
            entry.markerKey, entry.reachKey = nil, nil -- new tint: rebuild the lines too
        end
        rebuild(self, entry, base, function()
            return markerVertices(light)
        end, 'marker', 'EditorLightMarker')
        if entry.marker then
            Assign.color(entry.marker, color)
        end
        -- Only the selected light shows its reach, so a level full of lights stays readable.
        local selected = selection:has(light)
        rebuild(self, entry, selected and base or false, function()
            return selected and reachVertices(light, selected) or {}
        end, 'reach', 'EditorLightReach')
        if entry.reach then
            Assign.color(entry.reach, color)
        end
        if not entry.root.visible then
            entry.root.visible = true
        end
        -- Keep the icon a constant size on screen, however far the light is.
        local unit = 1
        if camera then
            -- Not ready before the camera has a view size (first frames, tests): keep the last size.
            local ok, _, _, depth = pcall(camera.project, camera, { p[1], p[2], p[3] })
            local perUnit = ok and depth and camera:pixelsPerUnitAt(depth)
            if perUnit and perUnit > 0 then
                unit = math.max(ICON_PIXELS / perUnit, 0.05)
            end
        end
        if entry.unit ~= unit then
            entry.unit = unit
            entry.pick.size = { unit * 2.2, unit * 2.2, unit * 2.2 }
            if entry.marker then
                entry.marker.scale = { unit * 3, unit * 3, unit * 3 }
            end
        end
    end
    for light, entry in pairs(self.entries) do
        if not alive[light] or light.destroyed then
            self:destroyEntry(entry)
            self.entries[light] = nil
        end
    end
end

-- The light a viz node belongs to (so a click on its marker selects the light), or nil.
function LightViz:ownerOf(node)
    return node and self.owners[node] or nil
end

function LightViz:release()
    for light, entry in pairs(self.entries) do
        self:destroyEntry(entry)
        self.entries[light] = nil
    end
end

return LightViz
