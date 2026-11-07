-- Diagnostic: bounding boxes of the Duke 69 parts in car-model space (for seat placement).
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    return setmetatable(Previous.new(manager), Tests)
end

function Tests:update() end

function Tests:draw()
    self.host = require('source.game.runtime.application').new(self.manager, 'multiplayerCars')
    self.host:load()
    local scene = self.host
    local asset = require('source.engine.import.models').load('scene://models/duke69.glb', scene.resources)
    for _, part in ipairs(asset.parts) do
        local lo, hi = { 1e9, 1e9, 1e9 }, { -1e9, -1e9, -1e9 }
        for _, v in ipairs(part.geometry.vertices) do
            for i = 1, 3 do
                lo[i], hi[i] = math.min(lo[i], v[i]), math.max(hi[i], v[i])
            end
        end
        print(('PART %-18s x %6.2f..%6.2f  y %6.2f..%6.2f  z %6.2f..%6.2f'):format(
            part.node.name, lo[1], hi[1], lo[2], hi[2], lo[3], hi[3]))
    end
    katsa.event.quit()
end

return Tests
