local T = {}
T.__index = T

function T.new(manager)
    return setmetatable({ manager = manager, count = 0 }, T)
end

function T:update() end

function T:check(ok, label)
    assert(ok, label)
    self.count = self.count + 1
    print('PASS v77 ' .. label)
end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    local Snapshot = require('source.engine.core.valueSnapshot')
    local baseline = os.getenv('KATSA_BASELINE')
    if baseline then
        local original = assert(loadfile(baseline .. '/source/engine/core/valueSnapshot.lua'))()
        local old, current = {}, {}
        local random = katsa.math.newRandomGenerator(77)
        for round = 1, 1000 do
            local value = {}
            for i = 1, random:random(0, 20) do
                if random:random(0, 1) == 0 then
                    value[i] = false
                else
                    value[i] = random:random(-10, 10)
                end
            end
            if round % 17 == 0 then
                value = round
            end
            local a, b = original.vector(old, 'v', value), Snapshot.vector(current, 'v', value)
            assert(a == b, 'Snapshot change flags differ')
            if type(value) == 'table' then
                assert(#old.v == #current.v, 'Snapshot lengths differ')
                for i = 1, #old.v do
                    assert(old.v[i] == current.v[i], 'Snapshot values differ')
                end
            else
                assert(old.v == current.v, 'Scalar snapshot values differ')
            end
        end
        self:check(true, '1000 growing/shrinking vector and scalar edits match v76 snapshots')
    end
    local scene = self.manager:switch(require('source.game.runtime.game').new, 'combined')
    local r, w, c = scene.renderer, scene.world, scene.camera
    w.environment.shadows.enabled, w.environment.gizmos.enabled = false, false
    w.environment.render.frameCache = false
    r:draw(w, c, 1, true)
    self:check(
        r.batches.attributeAttachments == 24 and r.batches.attributeDetachments == 16,
        'Three opaque groups attach 24 attributes and remove 16 at the pass boundary'
    )
    for _, group in ipairs(r.batches.groups) do
        self:check(
            not group.example.geometry.mesh:detachAttribute('instanceRow1'),
            'Instanced attributes are absent after the color pass'
        )
    end
    local cube = w.byName['Cube10.2']
    local a = r.canvas:newImageData()
    r:invalidate()
    r:draw(w, c, 1, true)
    local b = r.canvas:newImageData()
    self:check(
        a:getString() == b:getString(),
        'Retained group attachment order matches full rebuilding'
    )
    a:release()
    b:release()
    local batch = require('source.engine.graphics.pipeline.batches').new()
    batch:prepare({ cube })
    local success = pcall(function()
        batch:draw({
            drawBatch = function(_, group)
                batch:upload(group)
                error('Controlled callback failure')
            end,
        })
    end)
    batch:release()
    self:check(
        not success and not cube.geometry.mesh:detachAttribute('instanceRow1'),
        'Resource release cleans attached buffers after an interrupted pass'
    )
    print('PASSED ' .. self.count .. ' focused v77 checks')
    -- The established suite exercises dynamic shadows, opacity, probing and filters.
    require('validation.tests.versions.v76.runtime').new(self.manager):draw()
end

return T
