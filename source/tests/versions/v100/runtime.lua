local T = {}

local function extra(test)
    local Coverage = require('source.engine.graphics.occlusion.coverage')
    local original =
        assert(loadstring(katsa.filesystem.read('source/tests/fixtures/v99-coverage.lua')))()
    local random = katsa.math.newRandomGenerator(6197)
    local state = {}
    for iteration = 1, 400 do
        local x, y = random:random(-25, 75), random:random(-25, 75)
        local width, height = random:random(1, 70), random:random(1, 70)
        local points = { x, y, x + width, y, x + width, y + height, x, y + height }
        local polygons = {}
        for i = 1, random:random(2, 20) do
            local a, b = random:random(-60, 100), random:random(-60, 100)
            local w, h = random:random(1, 130), random:random(1, 130)
            local polygon = {
                { a, b, 5 },
                { a + w, b, 5 },
                { a + w, b + h, 5 },
                { a, b + h, 5 },
                sign = 1,
                depth = random:random(1, 15),
            }
            Coverage.describe(polygon)
            polygons[i] = polygon
        end
        local depth = random:random(1, 30)
        state.unionBudget = random:random(0, 1024)
        local reference = { unionBudget = state.unionBudget }
        local expected = original.test(points, depth, polygons, nil, reference)
        local actual = Coverage.test(points, depth, polygons, nil, state)
        assert(
            actual == expected and state.unionBudget == reference.unionBudget,
            'Coverage or exact work budget changed at ' .. iteration
        )
    end
    test:check(
        true,
        'Reusable subtraction arrays preserve v99 decisions and budgets across 400 varied queries'
    )
    if state.coverageScratch then
        test:check(
            #state.coverageScratch.points <= 385 and #state.coverageScratch.lists <= 193,
            'Coverage scratch retains bounded numeric arrays rather than scenes'
        )
    end
    local scene = assert(test.manager:switch(require('source.game.runtime.game').new, 'occlusion'))
    local Projection = require('source.engine.graphics.occlusion.projection')
    local reference =
        assert(loadstring(katsa.filesystem.read('source/tests/fixtures/v99-projection.lua')))()
    local a, b = {}, {}
    for frame = 1, 80 do
        scene.camera.position.X = math.sin(frame / 11) * 90
        scene.camera.rotation.Y = math.sin(frame / 17) * 100
        scene.camera:update(810, 456)
        for _, object in ipairs({ scene.demo.wall, scene.world.objects[1], scene.world.objects[20] }) do
            local old = reference.bounds(object, scene.camera, a)
            local new = Projection.bounds(object, scene.camera, b)
            assert((old ~= nil) == (new ~= nil), 'Near-plane projection validity differs')
            if old then
                for i = 1, 5 do
                    assert(a[i] == b[i], 'Corner projection arithmetic changed')
                end
            end
        end
    end
    test:check(true, 'Shared AABB products preserve exact projected bounds and near-plane validity')
end

function T.new(manager)
    local base = require('source.tests.versions.v99.runtime').new(manager)
    local finish = base.finish
    base.finish = function(test)
        extra(test)
        finish(test)
        print('PASSED ' .. test.count .. ' v100 regression/integration checks')
    end
    return base
end

return T
