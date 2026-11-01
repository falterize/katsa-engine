local T = {}
T.__index = T

function T.new(manager)
    return setmetatable({ manager = manager }, T)
end

function T:update() end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    local s = self.manager:switch(require('source.game.runtime.game').new, 'combined')
    local base = assert(os.getenv('KATSA_BASELINE'))
    local original = assert(loadfile(base .. '/source/engine/core/valueSnapshot.lua'))()
    local current = require('source.engine.core.valueSnapshot')
    local state = require('source.engine.graphics.pipeline.renderState')
    local oldFields = state.fields
    state.fields = original.fields
    local oldCache = assert(loadfile(base .. '/source/engine/graphics/pipeline/frameCache.lua'))()
    state.fields = current.fields
    local newCache = assert(
        loadfile(katsa.filesystem.getSource() .. '/source/engine/graphics/pipeline/frameCache.lua')
    )()
    state.fields = oldFields
    local renderers = { { shadows = {}, lights = {} }, { shadows = {}, lights = {} } }
    local callbacks = {
        function()
            oldCache.inspect(renderers[1], s.world, s.camera, 1, true)
        end,
        function()
            newCache.inspect(renderers[2], s.world, s.camera, 1, true)
        end,
    }
    for _, cb in ipairs(callbacks) do
        for i = 1, 40 do
            cb()
        end
    end
    for round = 1, 5 do
        for i, cb in ipairs(callbacks) do
            collectgarbage('collect')
            local start = katsa.timer.getTime()
            for j = 1, 500 do
                cb()
            end
            print('DEPENDENCIES', round, i, (katsa.timer.getTime() - start) * 1000 / 500)
        end
    end
    s.renderer:draw(s.world, s.camera, 1, true)
    local oldBatches = assert(loadfile(base .. '/source/engine/graphics/pipeline/batches.lua'))()
    local newBatches = require('source.engine.graphics.pipeline.batches')
    local batches = { oldBatches.new(), newBatches.new() }
    local callbacks = {}
    for i, batch in ipairs(batches) do
        batch:prepare(s.renderer.opaque)
        callbacks[i] = function()
            batch:draw({
                drawBatch = function(_, group)
                    local mesh = batch:upload(group)
                    batch:detach(mesh)
                end,
            })
        end
        callbacks[i]()
    end
    for round = 1, 5 do
        for i, cb in ipairs(callbacks) do
            local start = katsa.timer.getTime()
            for j = 1, 2000 do
                cb()
            end
            print('ATTRIBUTES', round, i, (katsa.timer.getTime() - start) * 1000 / 2000)
        end
    end
    print('ATTRIBUTE_CALLS', batches[2].attributeAttachments, batches[2].attributeDetachments)
    for _, batch in ipairs(batches) do
        batch:release()
    end
    katsa.event.quit()
end

return T
