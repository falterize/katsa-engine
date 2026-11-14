-- OneShot: plays `shot` once over `input` when its request is triggered (a gunshot, a hit reaction,
-- a wave). The shot fades in and out and may be limited to some bones.
--
--   { type = 'OneShot', input = locomotion, shot = { clip = 'Wave' }, request = 'wave',
--     fadeIn = 0.1, fadeOut = 0.2, filter = { 'Arm_R' }, filterChildren = true }
--   tree:trigger('wave')              -- starts it; again while playing: `restart = true` restarts it
--   tree:trigger('stopWave')          -- `abort = 'stopWave'` fades it out early
--
-- `mode = 'Add'` adds the shot's difference to its first frame instead of replacing the pose.
local Layers = require('../layers')

local OneShot = {}
OneShot.__index = OneShot

function OneShot.new(definition, build)
    assert(type(definition.request) == 'string', 'OneShot needs a request parameter name')
    local input, shot = build(definition.input), build(definition.shot)
    local leaves = {}
    shot:collect(leaves)
    for _, leaf in ipairs(leaves) do
        leaf.loop = false
    end
    local additive = definition.mode == 'Add'
    Layers.apply(shot, {
        boost = not additive and 1 or nil,
        additive = additive,
        reference = definition.reference,
        filter = definition.filter,
        children = definition.filterChildren,
    })
    return setmetatable({
        kind = 'OneShot',
        definition = definition,
        request = definition.request,
        abort = definition.abort,
        fadeIn = definition.fadeIn or 0.1,
        fadeOut = definition.fadeOut or 0.1,
        restartOnRequest = definition.restart == true,
        sync = definition.sync == true,
        active = false,
        time = 0,
        children = { input, shot },
    }, OneShot)
end

function OneShot:collect(list)
    for _, child in ipairs(self.children) do
        child:collect(list)
    end
end

-- Seconds the shot lasts: its longest clip at its own speed.
function OneShot:length()
    if not self.shotLength then
        local leaves, longest = {}, 0
        self.children[2]:collect(leaves)
        for _, leaf in ipairs(leaves) do
            longest = math.max(longest, leaf:duration() / math.max(leaf.speed, 1e-6))
        end
        self.shotLength = longest > 0 and longest or nil
    end
    return self.shotLength
end

function OneShot:isActive()
    return self.active
end

function OneShot:evaluate(weight, scale, context)
    local params = context.tree.params
    if params[self.request] and (not self.active or self.restartOnRequest) then
        self.active, self.time, self.aborting = true, 0, nil
        self.children[2]:restart()
    end
    if self.abort and params[self.abort] and self.active and not self.aborting then
        local length = self:length() or 0
        self.aborting = true
        self.time = math.max(self.time, length - self.fadeOut)
    end
    context:group(self)
    self.children[1]:evaluate(weight, scale, context)
    if not self.active then
        return
    end
    self.time = self.time + context.dt * scale
    local length = self:length() or self.time
    local envelope = 1
    if self.fadeIn > 0 then
        envelope = math.min(envelope, self.time / self.fadeIn)
    end
    if self.fadeOut > 0 then
        envelope = math.min(envelope, (length - self.time) / self.fadeOut)
    end
    if self.time >= length then
        self.active, self.aborting = false, nil
        return
    end
    self.children[2]:evaluate(weight * math.max(0, math.min(1, envelope)), scale, context)
end

function OneShot:restart()
    self.active, self.aborting = false, nil
    self.children[1]:restart()
end

function OneShot:finished()
    return not self.active
end

return OneShot
