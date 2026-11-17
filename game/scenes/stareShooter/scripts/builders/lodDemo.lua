local Mesh = require('source.engine.composition.mesh')
local Geometry = require('source.engine.graphics.geometry.primitives')
local Level = require('./level')

-- Level of detail on show (needs `plugins = { 'lod' }`): two rows of trees stand in front of the
-- character at the start (the camera looks toward -Z). Walk along them and watch the crowns change:
--   left row   `Hard`  switches at once (fadeTime 0)
--   right row  `Fade`  cross-fades over 0.4 s
-- Every level has its own colour and number of facets, so a switch is easy to see; a real game
-- would give all levels the same texture. Only level 0 casts a shadow (shadowLevel 0). The last
-- level before a tree disappears is a flat purple billboard that faces the camera.
-- `demo:setReach(meters)` moves every switch point at once (the maximum distance is where the
-- billboard stops being drawn); a small value shows all levels up close.
local LodDemo = {}
LodDemo.__index = LodDemo

-- Where each level starts, as fractions of the reach; the last one is the reach itself.
local FRACTIONS = { 0.17, 0.37, 0.64, 1 }
LodDemo.defaultReach = 70
LodDemo.minReach = 8
LodDemo.maxReach = 120

-- Crown detail per level: sphere segments and rings, and a tint.
local LEVELS = {
    { segments = 28, rings = 18, color = { 0.18, 0.62, 0.22, 1 } },
    { segments = 10, rings = 6, color = { 0.78, 0.82, 0.2, 1 } },
    { segments = 5, rings = 3, color = { 0.92, 0.5, 0.14, 1 } },
}
local ROWS = {
    { name = 'Hard', title = 'Hard switch', x = -7, fadeTime = 0 },
    { name = 'Fade', title = 'Fade 0.4 s', x = 7, fadeTime = 0.4 },
}
local COUNT, START, SPACING = 7, 14, 8

local function crownGeometries(scene)
    local list = {}
    for index, level in ipairs(LEVELS) do
        list[index] = Geometry.rounded('sphere', level.segments, level.rings)
        scene.resources:own(list[index].mesh)
    end
    return list
end

-- One level: a trunk and a crown inside a Node3D (the last level is a crown on a short trunk).
local function level(world, name, index, crowns, parent)
    local node = world:create('Node3D', { name = name }, parent)
    local settings = LEVELS[index]
    Mesh.create(world, {
        name = name .. 'Trunk',
        size = { 0.45, 1.8, 0.45 },
        position = { 0, 0.9, 0 },
        color = { 0.4, 0.26, 0.14, 1 },
        castShadow = index == 1,
    }, node)
    Mesh.create(world, {
        name = name .. 'Crown',
        geometry = crowns[index],
        size = { 2.6, 2.6, 2.6 },
        position = { 0, 2.8, 0 },
        color = settings.color,
        castShadow = index == 1,
    }, node)
    return node
end

local function label(world, text, position, parent)
    local board = world:create('BillboardUI', {
        name = 'LodLabel' .. text,
        position = position,
        size = { 0, 3, 0, 0.6 },
        sizeMode = 'World3D',
        canvasSize = { 0, 500, 0, 100 },
        onTop = true,
        maxDistance = 120,
    }, parent)
    board.ui:create('Label', {
        size = { 1, 0, 1, 0 },
        text = text,
        fontSize = 48,
        textColor = { 1, 1, 1 },
        backgroundColor = { 0.05, 0.1, 0.16 },
        backgroundTransparency = 0.25,
    }, board.ui.content)
end

-- The distances text of a group for a reach in meters, for example '12, 26, 45, 70'.
local function distancesFor(reach)
    local parts = {}
    for index, fraction in ipairs(FRACTIONS) do
        parts[index] = ('%.1f'):format(reach * fraction)
    end
    return table.concat(parts, ', ')
end

function LodDemo:setReach(reach)
    self.reach = math.max(LodDemo.minReach, math.min(LodDemo.maxReach, reach))
    local text = distancesFor(self.reach)
    for _, group in ipairs(self.groups) do
        group.distances = text
    end
end

function LodDemo.create(scene)
    local world = scene.world
    local crowns = crownGeometries(scene)
    local folder = world:create('Node3D', { name = 'LodDemo' })
    -- The start ground is only 20 m wide; this strip carries the trees further out.
    local length = START + SPACING * COUNT - 10
    Mesh.create(world, {
        name = 'LodField',
        geometry = Level.tiledPlane(scene, 10),
        size = { 40, 0, length },
        position = { 0, 0, 10 + length / 2 },
        receiveShadow = true,
        surfaceAppearance = { colorMap = 'scene://textures/ground.png', roughness = 1 },
    }, folder)
    local groups = {}
    for _, row in ipairs(ROWS) do
        for index = 1, COUNT do
            local name = row.name .. 'Tree' .. index
            local group = world:create('LODGroup', {
                name = name,
                position = { row.x, 0, START + SPACING * (index - 1) },
                distances = distancesFor(LodDemo.defaultReach),
                radius = 3,
                billboardImage = 'scene://textures/lodTree.png',
                billboardWidth = 3.2,
                billboardHeight = 4.6,
                fadeTime = row.fadeTime,
                shadowLevel = 0,
            }, folder)
            for number = 1, #LEVELS do
                level(world, name .. 'L' .. (number - 1), number, crowns, group)
            end
            groups[#groups + 1] = group
        end
        label(world, row.title, { row.x, 6.5, START + 4 }, folder)
    end
    return setmetatable({ scene = scene, groups = groups, reach = LodDemo.defaultReach }, LodDemo)
end

return LodDemo
