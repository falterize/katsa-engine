local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
-- Query the backend BVH, then perform exact narrow phase outside traversal callbacks.
local O = require('./valueTypes')
local bit = require('bit')

local Triggers = {}

local function clear(t)
    for key in pairs(t) do
        t[key] = nil
    end
end

function Triggers.step(physics)
    if not next(physics.triggerBodies) then
        return
    end
    local state = physics._triggerState
    if not state then
        state = {
            matrix = O.CollisionMatrix.new(),
            result = O.DetectorResult.new(),
            triggers = {},
            candidates = {},
            seen = {},
            callback = O.AabbTestCallback.new(),
        }
        physics._triggerState = state
        state.callback.process = function(_, shape)
            local body = shape.userData
            if
                body
                and body ~= state.sensor
                and not body.destroyed
                and body.colliderEnabled ~= false
                and not state.seen[body]
                and bit.band(physics.groups[body.group], physics.masks[state.sensor.group]) ~= 0
                and bit.band(physics.groups[state.sensor.group], physics.masks[body.group]) ~= 0
            then
                state.seen[body] = true
                state.candidates[#state.candidates + 1] = body
            end
        end
    end
    local spent = 0
    local sensors = state.triggers
    clear(sensors)
    for body in pairs(physics.triggerBodies) do
        sensors[#sensors + 1] = body
    end
    for _, body in ipairs(sensors) do
        if not body.destroyed then
            local previous = body.overlaps or {}
            body.overlaps = previous
            local current = body._overlapScratch or {}
            clear(current)
            local candidates = state.candidates
            clear(candidates)
            clear(state.seen)
            if body.isTrigger and body.colliderEnabled ~= false and body._inWorld then
                state.sensor = body
                for _, shape in ipairs(body.shapes) do
                    physics.stats.triggerQueries = physics.stats.triggerQueries + 1
                    physics.world:aabbTest(shape.raw:getAabb(), state.callback)
                end
                physics.stats.triggerCandidates = physics.stats.triggerCandidates + #candidates
                -- No events are emitted from a native BVH callback: mutation is deferred safely.
                for _, other in ipairs(candidates) do
                    if not other.destroyed then
                        local hit = false
                        for _, a in ipairs(body.shapes) do
                            for _, b in ipairs(other.shapes) do
                                if not hit and a.raw:getAabb():overlap(b.raw:getAabb()) then
                                    physics.stats.triggerPairs = physics.stats.triggerPairs + 1
                                    spent = spent + 1
                                    assert(
                                        spent <= physics.maxTriggerPairs,
                                        'Trigger narrow-phase budget exceeded; reduce active '
                                            .. 'trigger candidates'
                                    )
                                    local ga, gb = a.raw:getGeometry(), b.raw:getGeometry()
                                    state.result:clear()
                                    state.matrix:getDetector(ga:getType(), gb:getType()):detect(
                                        state.result,
                                        ga,
                                        gb,
                                        a.raw:getTransform(),
                                        b.raw:getTransform(),
                                        nil
                                    )
                                    hit = state.result.numPoints > 0
                                        and state.result:getMaxDepth() >= 0
                                end
                            end
                        end
                        if hit then
                            current[other] = true
                            if not previous[other] then
                                body.node:emit('triggerEntered', other)
                            end
                        end
                        if body.destroyed then
                            break
                        end
                    end
                end
            end
            if not body.destroyed then
                for other in pairs(previous) do
                    if not current[other] then
                        body.node:emit('triggerExited', other)
                    end
                end
                if not body.destroyed then
                    body.overlaps = current
                    body._overlapScratch = previous
                    clear(previous)
                    if not body.isTrigger then
                        physics.triggerBodies[body] = nil
                    end
                end
            end
        end
    end
    -- Reusable arrays/maps must not retain removed bodies between steps.
    clear(sensors)
    clear(state.candidates)
    clear(state.seen)
    state.sensor = nil
end

return Triggers
