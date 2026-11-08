-- Diagnostic (not pass/fail): how the authored shading of every dentable Duke 69 part is
-- classified (smooth or flat) at several thresholds.
--   xvfb-run -a luajit tools/dev/katsa.lua . --test-v108.7.shading
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.frame = 0
    return self
end

function Tests:update() end

function Tests:draw()
    self.frame = self.frame + 1
    if self.frame ~= 2 then
        return
    end
    local Models = require('source.engine.import.models')
    local Resources = require('source.engine.core.resources')
    local resources = Resources.new and Resources.new() or self.manager.resources
    local path = 'source/game/scenes/multiplayerCars/assets/models/duke69.glb'
    local ok, asset = pcall(Models.load, path, resources)
    if not ok then
        print('LOAD FAILED', asset)
        katsa.event.quit()
        return
    end
    for _, part in ipairs(asset.parts) do
        local rest = part.geometry.vertices
        local counts = { [0.998] = 0, [0.9999] = 0, [0.999999] = 0 }
        local tris, minCos = #rest / 3, 1
        for first = 1, #rest - 2, 3 do
            local a, b, c = rest[first], rest[first + 1], rest[first + 2]
            local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
            local wx, wy, wz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
            local nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
            local l = math.sqrt(nx * nx + ny * ny + nz * nz)
            if l > 1e-12 then
                nx, ny, nz = nx / l, ny / l, nz / l
                local worst = 1
                for i = 0, 2 do
                    local v = rest[first + i]
                    worst = math.min(worst, math.abs(nx * v[6] + ny * v[7] + nz * v[8]))
                end
                minCos = math.min(minCos, worst)
                for threshold in pairs(counts) do
                    if worst < threshold then
                        counts[threshold] = counts[threshold] + 1
                    end
                end
            end
        end
        print(string.format('%-14s tris %5d  smooth@0.998 %5d  @0.9999 %5d  @0.999999 %5d  min cos %.5f',
            part.node.name, tris, counts[0.998], counts[0.9999], counts[0.999999], minCos))
    end
    katsa.event.quit()
end

return Tests
