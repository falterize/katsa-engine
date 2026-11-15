local Arena = require('../../scripts.shared.arena')

-- The maps a round can be played on. They are templates in ServerStorage/Maps (never replicated);
-- `Maps:spawn` clones a random one into the world at the start of a round and `Maps:clear`
-- destroys the clone, so clients only ever see the map being played. Geometry is plain boxes
-- marked with the `Solid` attribute: each client gives them physics (scripts/game/solids.lua).
local Maps = {}
Maps.__index = Maps

local PROPERTIES = { 'kind', 'position', 'size', 'color' }

-- Boxes are { x, y, z, width, height, depth, color } around the arena centre (y is the box's
-- centre). Coins are { x, z, surface }: the coin floats 0.8 above the surface it stands on.
local FLOOR = 32
local SPECS = {
    {
        name = 'Ring Court',
        boxes = {
            { 0, 0, 0, FLOOR, 0.2, FLOOR, { 0.82, 0.5, 0.36, 1 } },
            { 0, 0.5, 0, 4, 1, 4, { 0.95, 0.78, 0.4, 1 } },
            { 11, 1.5, 11, 2, 3, 2, { 0.6, 0.35, 0.3, 1 } },
            { -11, 1.5, 11, 2, 3, 2, { 0.6, 0.35, 0.3, 1 } },
            { 11, 1.5, -11, 2, 3, 2, { 0.6, 0.35, 0.3, 1 } },
            { -11, 1.5, -11, 2, 3, 2, { 0.6, 0.35, 0.3, 1 } },
        },
        coins = {
            { 10, 0, 0.1 }, { 8, 6, 0.1 }, { 3, 10, 0.1 }, { -3, 10, 0.1 }, { -8, 6, 0.1 },
            { -10, 0, 0.1 }, { -8, -6, 0.1 }, { -3, -10, 0.1 }, { 3, -10, 0.1 }, { 0, 0, 1 },
        },
    },
    {
        name = 'Stepping Stones',
        boxes = {
            { 0, 0, 0, FLOOR, 0.2, FLOOR, { 0.2, 0.45, 0.5, 1 } },
            { 6, 0.4, 0, 4, 0.8, 4, { 0.55, 0.8, 0.75, 1 } },
            { 9, 0.8, 6, 4, 1.6, 4, { 0.5, 0.75, 0.7, 1 } },
            { 3, 1.2, 10, 4, 2.4, 4, { 0.45, 0.7, 0.65, 1 } },
            { -4, 0.8, 8, 4, 1.6, 4, { 0.5, 0.75, 0.7, 1 } },
            { -9, 0.4, 2, 4, 0.8, 4, { 0.55, 0.8, 0.75, 1 } },
            { -6, 0.8, -6, 4, 1.6, 4, { 0.5, 0.75, 0.7, 1 } },
            { 2, 1.2, -9, 4, 2.4, 4, { 0.45, 0.7, 0.65, 1 } },
            { 10, 0.6, -6, 4, 1.2, 4, { 0.5, 0.75, 0.7, 1 } },
        },
        coins = {
            { 6, 0, 0.8 }, { 9, 6, 1.6 }, { 3, 10, 2.4 }, { -4, 8, 1.6 }, { -9, 2, 0.8 },
            { -6, -6, 1.6 }, { 2, -9, 2.4 }, { 10, -6, 1.2 }, { 0, 0, 0.1 }, { 0, 3, 0.1 },
        },
    },
    {
        name = 'Crossroads',
        boxes = {
            { 0, 0, 0, FLOOR, 0.2, FLOOR, { 0.45, 0.5, 0.78, 1 } },
            { 0, 1, 7, 2, 2, 10, { 0.85, 0.85, 0.92, 1 } },
            { 0, 1, -7, 2, 2, 10, { 0.85, 0.85, 0.92, 1 } },
            { 7, 1, 0, 10, 2, 2, { 0.85, 0.85, 0.92, 1 } },
            { -7, 1, 0, 10, 2, 2, { 0.85, 0.85, 0.92, 1 } },
            { 0, 0.3, 0, 3, 0.6, 3, { 1, 0.85, 0.4, 1 } },
        },
        coins = {
            { 0, 0, 0.6 }, { 10, 10, 0.1 }, { -10, 10, 0.1 }, { 10, -10, 0.1 }, { -10, -10, 0.1 },
            { 7, 3, 0.1 }, { -7, -3, 0.1 }, { 3, -7, 0.1 }, { -3, 7, 0.1 }, { 13, 0, 0.1 },
        },
    },
}

local function addBox(world, parent, center, box, name)
    local mesh = world:create('Mesh3D', {
        name = name,
        position = { center[1] + box[1], center[2] + box[2], center[3] + box[3] },
        size = { box[4], box[5], box[6] },
        color = box[7],
        replicated = true,
        replicatedProperties = PROPERTIES,
    }, parent)
    mesh:setAttribute('Solid', true)
    return mesh
end

-- storage: the ServerStorage container. Builds the templates once.
-- parent: the world's World3D node, where a round's map is cloned.
function Maps.new(world, storage, parent)
    local self = setmetatable({ world = world, parent = parent, last = nil }, Maps)
    self.folder = world:create('Folder', { name = 'Maps' }, storage)
    for _, spec in ipairs(SPECS) do
        local template = world:create('Folder', { name = spec.name }, self.folder)
        for index, box in ipairs(spec.boxes) do
            -- Mesh names are unique per world.
            addBox(world, template, Arena.arena, box, spec.name:gsub('%s', '') .. 'Part' .. index)
        end
        -- The coin points travel with the template as attributes of the folder.
        template:setAttribute('CoinCount', #spec.coins)
        self[spec.name] = spec
    end
    return self
end

-- Clones a random template (never the one just played) into the world. Returns the clone and the
-- absolute coin positions.
function Maps:spawn()
    local templates = self.folder.children
    local pick
    repeat
        pick = templates[math.random(#templates)]
    until #templates == 1 or pick.name ~= self.last
    self.last = pick.name
    local map = pick:clone({ name = 'Map' }, self.parent)
    map:setAttribute('Title', pick.name)
    for _, node in ipairs(map:getDescendants()) do
        if node.className == 'Mesh3D' then
            node.replicated, node.replicatedProperties = true, PROPERTIES
        end
    end
    map.replicated = true
    local coins = {}
    for _, point in ipairs(self[pick.name].coins) do
        coins[#coins + 1] = { Arena.arena[1] + point[1], point[3] + 0.8, Arena.arena[3] + point[2] }
    end
    self.current, self.spec = map, self[pick.name]
    return map, coins, pick.name
end

function Maps:clear()
    if self.current and not self.current.destroyed then
        self.current:destroy()
    end
    self.current, self.spec = nil, nil
end

-- The height of the ground at (x, z): the highest box of the current map there, else 0. The
-- server has no physics, so bots use this to stand on the map.
function Maps:heightAt(x, z)
    local top = 0
    if self.spec then
        for _, box in ipairs(self.spec.boxes) do
            local cx, cz = Arena.arena[1] + box[1], Arena.arena[3] + box[3]
            if math.abs(x - cx) <= box[4] / 2 and math.abs(z - cz) <= box[6] / 2 then
                top = math.max(top, box[2] + box[5] / 2)
            end
        end
    end
    return top
end

return Maps
