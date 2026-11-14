-- AnimationTree: a graph of blend nodes that drives the AnimationTracks of one Animator.
--
--   local tree = AnimationTree.new(animator, {
--       type = 'StateMachine', start = 'Ground',
--       states = {
--           Ground = { type = 'Blend1D', param = 'speed', points = {
--               { 0, 'Player_Idle' }, { 1, 'Player_Walk' } } },
--           Air = { clip = 'Player_Fall' },
--       },
--       transitions = {
--           { from = 'Ground', to = 'Air', when = function(p) return not p.grounded end },
--           { from = 'Air', to = 'Ground', when = 'grounded' },
--       },
--   })
--   tree:set('speed', 0.6)
--
-- Nodes: Animation (a clip), Blend (two inputs), Blend1D / Blend2D (clips over one or two
-- parameters), TimeScale, StateMachine. Every update the graph assigns each clip a weight; the
-- tree turns that into `weight` and `speed` of one AnimationTrack per clip, so masks, layers
-- (`order`), markers and root motion of the Animator keep working. Blend1D and Blend2D keep
-- their clips in step (their speeds are scaled so all clips share one phase) unless `sync = false`.
local Graph = require('./graph')
local Layers = require('./layers')

local Tree = {}
Tree.__index = Tree

local context = {}
context.__index = context

function context:add(leaf, weight, scale)
    self.weights[leaf] = (self.weights[leaf] or 0) + weight
    self.scales[leaf] = scale
end

function context:group(node)
    if node.sync then
        self.groups[#self.groups + 1] = node
    end
end

function Tree.new(animator, definition)
    assert(animator and animator.load and animator.addController, 'AnimationTree needs an Animator')
    local self = setmetatable({
        animator = animator,
        params = {},
        triggers = {},
        active = true,
        root = Graph.build(definition),
        leaves = {},
    }, Tree)
    self.root:collect(self.leaves)
    for _, leaf in ipairs(self.leaves) do
        local settings = {
            looped = leaf.loop,
            order = (leaf.definition.order or 0) + (leaf.orderBoost or 0),
            boneMask = Layers.mask(leaf, animator.model),
            retarget = leaf.definition.retarget,
            speed = leaf.speed,
        }
        leaf.track = animator:load(leaf.definition.clip, settings)
        leaf.track.additive = leaf.additive
        leaf.track.additiveReference = leaf.additiveReference
        leaf.track:play(0, leaf.speed, 0)
    end
    self.context = setmetatable({ tree = self, weights = {}, scales = {}, groups = {}, dt = 0 }, context)
    animator:addController(self)
    return self
end

function Tree:set(name, value)
    self.params[name] = value
end

function Tree:get(name)
    return self.params[name]
end

-- A trigger is a parameter that stays true for exactly one update.
function Tree:trigger(name)
    self.params[name] = true
    self.triggers[#self.triggers + 1] = name
end

-- Moves the state machine named `machine` (the root when it is one) to `state`: along the chain of
-- transitions between the two when there is one, else straight there.
function Tree:travel(state, machine, fade)
    local node = machine and self:find(machine) or self:firstMachine()
    assert(node and node.travel, 'travel needs a StateMachine')
    node:travel(state, fade, self)
end

-- First graph node with the given `name` (set it in the definition), or nil.
function Tree:find(name)
    local function search(node)
        if node.name == name then
            return node
        end
        for _, child in ipairs(node.children) do
            local found = search(child)
            if found then
                return found
            end
        end
    end
    return search(self.root)
end

-- The first StateMachine of the graph (depth first), or nil.
function Tree:firstMachine()
    local function search(node)
        if node.kind == 'StateMachine' then
            return node
        end
        for _, child in ipairs(node.children) do
            local found = search(child)
            if found then
                return found
            end
        end
    end
    return search(self.root)
end

-- Name of the active state of the first state machine in the graph (the root, or the first one
-- below it, for example under a OneShot); nil without one.
function Tree:state()
    local machine = self:firstMachine()
    return machine and machine.current or nil
end

function Tree:update(dt)
    if not self.active then
        return
    end
    local ctx = self.context
    for leaf in pairs(ctx.weights) do
        ctx.weights[leaf], ctx.scales[leaf] = nil, nil
    end
    for i = #ctx.groups, 1, -1 do
        ctx.groups[i] = nil
    end
    ctx.dt = dt
    self.root:evaluate(1, 1, ctx)

    -- Clips of a sync group run at speeds that keep one shared phase.
    local factor = self.factor or {}
    self.factor = factor
    for leaf in pairs(factor) do
        factor[leaf] = nil
    end
    for _, group in ipairs(ctx.groups) do
        local members = group.members
        if not members then
            members = {}
            group:collect(members)
            group.members = members
        end
        local weight, weighted = 0, 0
        for _, leaf in ipairs(members) do
            local w = ctx.weights[leaf] or 0
            weight, weighted = weight + w, weighted + w * leaf:duration()
        end
        if weight > 1e-6 and weighted > 1e-6 then
            local average = weighted / weight
            for _, leaf in ipairs(members) do
                if leaf:duration() > 0 then
                    factor[leaf] = leaf:duration() / average
                end
            end
        end
    end
    for _, leaf in ipairs(self.leaves) do
        local track = leaf.track
        leaf.lastWeight = ctx.weights[leaf] or 0
        track.weight = math.max(0, math.min(1, leaf.lastWeight))
        track.speed = leaf.speed * (ctx.scales[leaf] or 1) * (factor[leaf] or 1)
    end
    for i = #self.triggers, 1, -1 do
        self.params[self.triggers[i]] = nil
        self.triggers[i] = nil
    end
end

function Tree:destroy()
    self.animator:removeController(self)
    for _, leaf in ipairs(self.leaves) do
        if leaf.track and not leaf.track.destroyed then
            leaf.track:destroy()
        end
    end
    self.leaves = {}
end

return Tree
