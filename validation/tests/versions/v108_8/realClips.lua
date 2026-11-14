-- The new nodes on the real animated character: Blend2D weights, and Add2 / Sub2 move the pose in
-- opposite directions from the same base.
local Module = {}

local function rotations(asset)
    local list = {}
    for i, bone in ipairs(asset.nodes) do
        list[i] = { bone.rotation[1], bone.rotation[2], bone.rotation[3], bone.rotation[4] }
    end
    return list
end

local function dot(a, b)
    return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] + a[4] * b[4]
end

function Module.run(self)
    local Resources = require('source.engine.core.resources')
    local World3D = require('source.engine.world.world')
    local Models = require('source.engine.import.models')
    local resources = Resources.new(require('source.game.data.manifest'))
    local world = World3D.new(resources, require('source.game.data.settings').create())
    local asset = Models.load('assets/models/characters/player.glb', resources)
    local _, root = Models.instantiate(world, asset, { name = 'Hero' })
    local animator = asset.animator

    local function pose(definition, params)
        local node = world:create('AnimationTree', { definition = definition }, root)
        for name, value in pairs(params or {}) do
            node:set(name, value)
        end
        node:update()
        for _ = 1, 20 do
            animator:update(1 / 30)
        end
        local result = rotations(asset)
        node:destroy()
        return result
    end

    local space = {
        type = 'Blend2D',
        x = 'x',
        y = 'y',
        points = {
            { 0, 0, 'Player_Idle' },
            { 1, 0, 'Player_Walk' },
            { 0, 1, 'Player_Crouch' },
            { 1, 1, 'Player_Fall' },
        },
    }
    local node = world:create('AnimationTree', { definition = space }, root)
    node:set('x', 0.5)
    node:set('y', 0.5)
    node:update()
    animator:update(1 / 30)
    local total, active = 0, 0
    for _, track in ipairs(animator.tracks) do
        total = total + track.weight
        if track.weight > 0 then
            active = active + 1
        end
    end
    self:check(math.abs(total - 1) < 1e-3 and active >= 2, 'Blend2D on real clips shares one unit of weight')
    node:destroy()

    local base = 'Player_Idle'
    local plain = pose({ type = 'Add2', amount = 0, base = base, add = 'Player_Crouch' })
    local added = pose({ type = 'Add2', amount = 1, base = base, add = 'Player_Crouch' })
    local removed = pose({ type = 'Sub2', amount = 1, base = base, sub = 'Player_Crouch' })
    local moved, opposite = 0, 0
    for i = 1, #plain do
        local up = 1 - math.abs(dot(plain[i], added[i]))
        local down = 1 - math.abs(dot(plain[i], removed[i]))
        if up > 1e-4 then
            moved = moved + 1
        end
        if up > 1e-4 and down > 1e-4 then
            -- Adding and removing the same difference turns the bone in opposite directions.
            local middle = { 0, 0, 0, 0 }
            for k = 1, 4 do
                middle[k] = added[i][k] + removed[i][k] * (dot(added[i], removed[i]) < 0 and -1 or 1)
            end
            local length = math.sqrt(dot(middle, middle))
            local mixed = 0
            for k = 1, 4 do
                mixed = mixed + (middle[k] / length) * plain[i][k]
            end
            if math.abs(mixed) > 0.9999 then
                opposite = opposite + 1
            end
        end
    end
    self:check(moved > 0, 'An additive clip moves the pose of the real character')
    self:check(opposite > 0, 'Sub2 turns the bones the opposite way to Add2')
end

return Module
