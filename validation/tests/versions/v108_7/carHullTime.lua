-- Diagnostic: how long the car body takes to decompose, and what comes out.
local Tests = {}
Tests.__index = Tests

function Tests.new(manager)
    return setmetatable({ manager = manager }, Tests)
end

function Tests:update() end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    local Models = require('source.engine.import.models')
    local Decomposition = require('source.engine.physics.3d.decomposition')
    local resources = self.manager.resources:scope()
    local asset = Models.load('source/game/scenes/multiplayerCars/assets/models/duke69.glb', resources)
    io.stderr:write('P parts ', #asset.parts, '\n')
    local soup = {}
    for _, part in ipairs(asset.parts) do
        io.stderr:write('P ', part.node.name, ' ', #part.geometry.vertices, '\n')
        if part.node.name == 'Body' or part.node.name == 'Hood' or part.node.name == 'Trunkdoor' then
            for _, v in ipairs(part.geometry.vertices) do
                soup[#soup + 1] = { v[1], v[2], v[3] }
            end
        end
    end
    io.stderr:write('P soup ', #soup, '\n')
    local Grid = require('source.engine.physics.3d.decomposition.voxelGrid')
    local Planner = require('source.engine.physics.3d.decomposition.planner')
    local t = os.clock()
    local grid = Grid.build(soup, 28)
    io.stderr:write('P grid ', os.clock() - t, ' ', grid.nx, 'x', grid.ny, 'x', grid.nz, '\n')
    t = os.clock()
    local leaves, stats = Planner.plan(grid, { maxHulls = 6, concavity = 0.03 })
    io.stderr:write('P plan ', os.clock() - t, ' ', #leaves, '\n')
    t = os.clock()
    local hulls = Decomposition.decompose(soup, { maxHulls = 6, hullPoints = 24, concavity = 0.03, resolution = 28 })
    io.stderr:write('P hulls ', #hulls, ' s ', os.clock() - t, '\n')
    katsa.event.quit()
end

return Tests
