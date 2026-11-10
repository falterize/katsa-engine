-- AnimationTree graphs (Blend1D/2D, TimeScale, StateMachine) on a fake Animator, and clip
-- retargeting between skeletons with different rest poses and bone names.
local Tree = require('source.engine.animation.tree')
local Retarget = require('source.engine.animation.retarget')
local Schema = require('source.engine.editor.inspectors.schema')

local Tests = {}

local function near(a, b, tolerance)
    return math.abs(a - b) <= (tolerance or 1e-4)
end

-- The part of the Animator the tree uses: clips by name, one track per load, controllers.
local function fakeAnimator(durations)
    local animator = { controllers = {}, tracks = {} }
    function animator:load(name, settings)
        local track = {
            clip = { name = name, duration = durations[name] },
            weight = 1,
            speed = settings.speed or 1,
            looped = settings.looped,
            timePosition = 0,
            state = 'Stopped',
        }
        function track:play(_, speed, weight)
            self.speed, self.weight, self.state = speed or self.speed, weight or self.weight, 'Playing'
        end
        function track:resume()
            self.state = 'Playing'
        end
        function track:destroy()
            self.destroyed = true
        end
        self.tracks[name] = track
        return track
    end
    function animator:addController(controller)
        self.controllers[#self.controllers + 1] = controller
    end
    function animator:removeController(controller)
        for i, c in ipairs(self.controllers) do
            if c == controller then
                table.remove(self.controllers, i)
            end
        end
    end
    return animator
end

local DURATIONS = { Idle = 1.0, Walk = 0.8, Run = 0.5, Jump = 0.6, Fall = 1.0 }

local function skeleton(names, restRotation, boneLength)
    local model = { nodes = {} }
    for i, name in ipairs(names) do
        model.nodes[i] = {
            name = name,
            index = i,
            rest = {
                translation = { 0, i == 1 and 0 or boneLength, 0 },
                rotation = restRotation,
                scale = { 1, 1, 1 },
            },
        }
    end
    return model
end

local function zRotation(degrees)
    local half = math.rad(degrees) / 2
    return { 0, 0, math.sin(half), math.cos(half) }
end

function Tests.run(tester)
    local animator = fakeAnimator(DURATIONS)
    local tree = Tree.new(animator, {
        type = 'StateMachine',
        start = 'Ground',
        fade = 0.2,
        states = {
            Ground = {
                type = 'Blend1D',
                param = 'speed',
                points = { { 0, 'Idle' }, { 1, 'Walk' }, { 3, 'Run' } },
            },
            Air = { type = 'TimeScale', scale = 'rate', child = { clip = 'Fall' } },
            Jumping = { clip = 'Jump', loop = false },
        },
        transitions = {
            { from = 'Ground', to = 'Jumping', when = 'jump' },
            { from = 'Jumping', to = 'Air', onFinish = true },
            { from = 'Air', to = 'Ground', when = 'grounded' },
        },
    })
    local tracks = animator.tracks
    tree:set('speed', 0.5)
    tree:update(1 / 60)
    tester:check(
        near(tracks.Idle.weight, 0.5) and near(tracks.Walk.weight, 0.5) and tracks.Run.weight == 0,
        'Blend1D shares the weight between the two neighbouring clips'
    )
    tester:check(
        near(tracks.Idle.speed / DURATIONS.Idle, tracks.Walk.speed / DURATIONS.Walk),
        'Synced blend clips keep one shared phase'
    )
    tree:set('speed', 3)
    tree:update(1 / 60)
    tester:check(near(tracks.Run.weight, 1) and tracks.Idle.weight == 0, 'Blend1D clamps at its ends')

    tree:trigger('jump')
    tree:update(0.1)
    tester:check(
        tree:state() == 'Jumping' and near(tracks.Run.weight, 1) and tracks.Jump.weight == 0,
        'A transition starts from the old state'
    )
    tree:update(0.1)
    tester:check(
        near(tracks.Run.weight, 0.5) and near(tracks.Jump.weight, 0.5),
        'A transition crossfades over its duration'
    )
    tree:update(0.2)
    tester:check(near(tracks.Jump.weight, 1) and tracks.Run.weight == 0, 'The fade completes')
    tester:check(tree.params.jump == nil, 'A trigger lasts one update')

    tracks.Jump.state = 'Paused' -- the non-looping clip finished
    tree:update(0.05)
    tester:check(tree:state() == 'Air', 'onFinish leaves a state when its clip ends')
    tree:set('rate', 2)
    tree:update(0.3)
    tester:check(near(tracks.Fall.speed, 2), 'TimeScale multiplies the clip speed')
    tree:set('grounded', true)
    tree:update(0.01)
    tester:check(tree:state() == 'Ground' and tracks.Jump.timePosition == 0, 'Entering a state restarts it')

    local plane = fakeAnimator(DURATIONS)
    local blend = Tree.new(plane, {
        type = 'Blend2D',
        x = 'x',
        y = 'y',
        points = { { 0, 0, 'Idle' }, { 0, 1, 'Walk' }, { 1, 0, 'Run' } },
    })
    blend:set('x', 0.3)
    blend:set('y', 0.3)
    blend:update(1 / 60)
    local sum = 0
    for _, name in ipairs({ 'Idle', 'Walk', 'Run' }) do
        sum = sum + plane.tracks[name].weight
    end
    tester:check(near(sum, 1), 'Blend2D weights add up to one')
    blend:set('x', 0)
    blend:set('y', 1)
    blend:update(1 / 60)
    tester:check(near(plane.tracks.Walk.weight, 1), 'Blend2D at a clip point plays that clip alone')
    blend:destroy()
    tester:check(plane.tracks.Walk.destroyed and #plane.controllers == 0, 'Destroying a tree frees its tracks')

    -- Retargeting: names differ by prefix, rests and bone lengths differ.
    local source = skeleton({ 'mixamorig:Hips', 'mixamorig:Spine' }, zRotation(0), 1)
    local target = skeleton({ 'Hips', 'Spine' }, zRotation(30), 2)
    local clip = {
        name = 'Wave',
        duration = 1,
        markers = {},
        channels = {
            {
                node = source.nodes[2],
                target = 'rotation',
                times = { { 0 }, { 1 } },
                values = { zRotation(0), zRotation(90) },
            },
            {
                node = source.nodes[2],
                target = 'translation',
                times = { { 0 }, { 1 } },
                values = { { 0, 1, 0 }, { 0, 1.5, 0 } },
            },
        },
    }
    local result = Retarget.clip(clip, target)
    local q = result.channels[1].values[2]
    local expected = zRotation(120)
    tester:check(
        result.channels[1].node == target.nodes[2]
            and near(q[3], expected[3]) and near(q[4], expected[4]),
        'Retargeting moves rotations onto the target rest pose'
    )
    tester:check(
        near(result.channels[2].values[2][2], 3),
        'Retargeting scales translations by the bone length ratio'
    )
    local lonely = skeleton({ 'Tail', 'Fin' }, zRotation(0), 1)
    local refused, message = Retarget.clip(clip, lonely)
    tester:check(refused == nil and message:find('boneMap'), 'A clip with no matching bones is refused')
    local mapped = Retarget.clip(clip, lonely, { boneMap = { ['mixamorig:Spine'] = 'Fin' } })
    tester:check(mapped and mapped.channels[1].node == lonely.nodes[2], 'boneMap pairs bones by hand')

    local Animator = require('source.engine.nodes').getClass('Animator')
    local host = setmetatable({ model = target }, { __index = Animator })
    local fitted = host:fitClip(clip, nil)
    tester:check(
        fitted ~= clip and host:fitClip(clip, nil) == fitted,
        'The Animator retargets a foreign clip once and reuses the result'
    )
    tester:check(host:fitClip(fitted, nil) == fitted, 'A clip of the model itself plays unchanged')

    -- The node on a real animated model: weights reach the real tracks and move the pose.
    local Resources = require('source.engine.core.resources')
    local World3D = require('source.engine.world.world')
    local Models = require('source.engine.import.models')
    local resources = Resources.new(require('source.game.data.manifest'))
    local world = World3D.new(resources, require('source.game.data.settings').create())
    local asset = Models.load('assets/models/characters/player.glb', resources)
    local _, root = Models.instantiate(world, asset, { name = 'Hero' })
    local node = world:create('AnimationTree', {
        definition = {
            type = 'Blend1D',
            param = 'speed',
            points = { { 0, 'Player_Idle' }, { 1, 'Player_Walk' } },
        },
    }, root)
    node:set('speed', 1)
    node:update()
    local heroAnimator = asset.animator
    for _ = 1, 20 do
        heroAnimator:update(1 / 30)
    end
    local walking = 0
    for _, track in ipairs(heroAnimator.tracks) do
        if track.clip.name == 'Player_Walk' and track._blendWeight > 0.99 then
            walking = walking + 1
        end
    end
    tester:check(walking == 1 and node:get('speed') == 1, 'AnimationTree drives the real tracks of a model')
    node:destroy()
    tester:check(#heroAnimator.controllers == 0, 'Destroying the node detaches it from the Animator')

    tester:check(
        Schema.keys(require('source.engine.nodes').getClass('AnimationTree'), {}) ~= nil
            and require('source.engine.nodes').getClass('AnimationTree').propertySchema.animator.kind
                == 'node',
        'AnimationTree is a node with inspector properties'
    )
end

return Tests
