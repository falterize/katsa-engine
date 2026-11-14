-- Node names with -col / -colonly create colliders when a model is instantiated (Godot style).
local AutoCollision = require('source.engine.import.autoCollision')
local Models = require('source.engine.import.models')
local World = require('source.engine.world.world')

local Module = {}

function Module.run(self)
    local base, kind = AutoCollision.parse('apple-colonly.001')
    self:check(base == 'apple' and kind == 'only', 'parse reads -colonly and Blender copy suffixes')
    base, kind = AutoCollision.parse('Wall-COL')
    self:check(base == 'Wall' and kind == 'visible', 'parse reads -col case-insensitively')
    self:check(AutoCollision.parse('column') == nil, 'plain names are not collision nodes')

    for _, backend in ipairs({ 'oimo', 'jolt' }) do
        local resources = self.manager.resources:scope()
        local world = World.new(resources)
        world:createPhysics({ backend = backend, gravity = { 0, 0, 0 } })
        local path = 'validation/tests/fixtures/models/autoCollision.glb'
        local model = Models.load(path, resources)
        local objects, root = Models.instantiate(world, model, { name = 'Level' })
        local byName = {}
        for _, node in ipairs(root:getDescendants()) do
            byName[node.name] = node
        end
        local bodies = model.collisionBodies
        self:check(#bodies == 3, backend .. ': three collision nodes create three bodies')
        world:updateNodes(1 / 60)

        local crate, colonly = byName['Level.crate'], byName['Level.crate-colonly']
        local wall, zone = byName['Level.wall-col'], byName['Level.zone-colonly']
        self:check(crate and crate.visible ~= false, backend .. ': the visual twin keeps rendering')
        self:check(colonly and colonly.visible == false, backend .. ': -colonly meshes are hidden')
        self:check(wall and wall.visible ~= false, backend .. ': -col meshes keep rendering')
        self:check(zone and zone.visible == false, backend .. ': a lone -colonly mesh is hidden')

        local function bodyOf(owner)
            for _, child in ipairs(owner.children) do
                if child:isA('Body3D') then
                    return child
                end
            end
        end
        self:check(bodyOf(crate) ~= nil, backend .. ': the -colonly collider attaches to its visual twin')
        self:check(bodyOf(wall) ~= nil, backend .. ': -col attaches a collider to its own mesh')
        self:check(bodyOf(colonly) == nil and bodyOf(zone) == nil,
            backend .. ': hidden meshes do not own bodies')
        for _, body in ipairs(bodies) do
            local collider = body.children[1]
            self:check(collider.status == 'Ready' and #body.physics.shapes > 0,
                backend .. ': ' .. body.name .. ' builds native shapes (' .. tostring(collider.status) .. ')')
        end

        local plain = Models.instantiate(world, Models.load(path, resources), { name = 'Plain', autoCollision = false })
        self:check(plain ~= nil, backend .. ': autoCollision = false skips bodies')
    end
end

return Module
