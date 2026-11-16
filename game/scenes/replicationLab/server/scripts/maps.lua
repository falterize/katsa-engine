local Arena = require('../../scripts.shared.arena')

-- The maps a round can be played on. Each is a prefab scene (assets/prefabs/maps/<name>) that
-- builds boxes marked with the `Solid` attribute (each client gives them physics,
-- scripts/game/solids.lua). `Maps:spawn` places a random one at the arena at the start of a round
-- and `Maps:clear` destroys it, so clients only ever see the map being played.
local Maps = {}
Maps.__index = Maps

local FOLDER = 'scene://prefabs/maps/'
local NAMES = { 'ringCourt', 'steppingStones', 'crossroads' }
local PROPERTIES = { 'kind', 'position', 'size', 'color' }

-- parent: the world's World3D node, where a round's map is placed.
function Maps.new(world, parent)
    local self = setmetatable({ world = world, parent = parent, last = nil, list = {} }, Maps)
    for _, name in ipairs(NAMES) do
        local packed = world.prefabs:load(FOLDER .. name)
        -- The prefab's own data module: boxes around its origin, and the coins on them.
        self.list[#self.list + 1] = { packed = packed, spec = packed:require('scripts.data') }
    end
    return self
end

-- Places a random map (never the one just played) at the arena. Returns the map node, the absolute
-- coin positions and the map's title.
function Maps:spawn()
    local pick
    repeat
        pick = self.list[math.random(#self.list)]
    until #self.list == 1 or pick.spec.title ~= self.last
    self.last = pick.spec.title
    local map = pick.packed:instantiate({ name = 'Map', position = Arena.arena }, self.parent)
    map:setAttribute('Title', pick.spec.title)
    for _, node in ipairs(map:getDescendants()) do
        if node.className == 'Mesh3D' then
            node.replicated, node.replicatedProperties = true, PROPERTIES
        end
    end
    map.replicated, map.replicatedProperties = true, { 'position' }
    local coins = {}
    for _, point in ipairs(pick.spec.coins) do
        coins[#coins + 1] =
            { Arena.arena[1] + point[1], Arena.arena[2] + point[3] + 0.8, Arena.arena[3] + point[2] }
    end
    self.current, self.spec = map, pick.spec
    return map, coins, pick.spec.title
end

function Maps:clear()
    if self.current and not self.current.destroyed then
        self.current:destroy()
    end
    self.current, self.spec = nil, nil
end

-- The height of the ground at (x, z) in world units: the highest box of the current map there
-- (boxes are placed around the arena, y included), else 0. The
-- server has no physics, so bots use this to stand on the map.
function Maps:heightAt(x, z)
    local top = 0
    if self.spec then
        for _, box in ipairs(self.spec.boxes) do
            local cx, cz = Arena.arena[1] + box[1], Arena.arena[3] + box[3]
            if math.abs(x - cx) <= box[4] / 2 and math.abs(z - cz) <= box[6] / 2 then
                top = math.max(top, Arena.arena[2] + box[2] + box[5] / 2)
            end
        end
    end
    return top
end

return Maps
