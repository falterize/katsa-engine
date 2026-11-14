-- New AnimationTree nodes on a fake Animator: Blend3, Add2/Add3, OneShot, Transition, TimeSeek,
-- filters, Blend2D triangulation and modes, and StateMachine switch modes, priority, travel, End.
local Tree = require('source.engine.animation.tree')

local Tests = {}

local function near(a, b, tolerance)
    return math.abs(a - b) <= (tolerance or 1e-3)
end

-- The part of the Animator the tree uses; every load keeps its settings on the track.
local function fakeAnimator()
    local animator = { controllers = {}, tracks = {} }
    function animator:load(name, settings)
        local track = { clip = { name = name, duration = 1 }, weight = 1, timePosition = 0, state = 'Stopped' }
        for key, value in pairs(settings) do
            track[key] = value
        end
        function track:range()
            return self.startTime or 0, math.min(self.endTime or self.clip.duration, self.clip.duration)
        end
        function track:play(_, speed, weight)
            self.speed, self.weight, self.state = speed or self.speed, weight or self.weight, 'Playing'
        end
        function track:resume()
            self.state = 'Playing'
        end
        function track:destroy() end
        self.tracks[name] = track
        return track
    end
    function animator:addController(controller)
        self.controllers[#self.controllers + 1] = controller
    end
    function animator:removeController() end
    return animator
end

local function build(definition)
    local animator = fakeAnimator()
    return Tree.new(animator, definition), animator.tracks
end

function Tests.run(tester)
    local tree, tracks = build({ type = 'Blend3', amount = 'x', a = 'A', b = 'B', c = 'C' })
    tree:set('x', -0.5)
    tree:update(0.1)
    tester:check(near(tracks.A.weight, 0.5) and near(tracks.B.weight, 0.5) and tracks.C.weight == 0, 'Blend3 mixes a and b below zero')
    tree:set('x', 1)
    tree:update(0.1)
    tester:check(near(tracks.C.weight, 1) and tracks.B.weight == 0, 'Blend3 ends on c at one')

    tree, tracks = build({
        type = 'Add3',
        amount = 'lean',
        base = 'Walk',
        minus = 'Left',
        plus = 'Right',
        filter = { 'Spine' },
    })
    tree:set('lean', -0.4)
    tree:update(0.1)
    tester:check(
        tracks.Walk.weight == 1 and not tracks.Walk.additive and tracks.Left.additive and near(tracks.Left.weight, 0.4) and tracks.Right.weight == 0,
        'Add3 adds the minus clip additively for a negative amount'
    )
    tester:check(tracks.Left.boneMask.Spine == 1, 'An additive node filter becomes the bone mask of its clips')

    tree, tracks = build({ type = 'Add2', amount = 0.5, base = 'Walk', add = 'Breathe', reference = 'rest' })
    tree:update(0.1)
    tester:check(
        tracks.Breathe.additive and tracks.Breathe.additiveReference == 'rest' and near(tracks.Breathe.weight, 0.5),
        'Add2 scales an additive clip by its amount'
    )

    tree, tracks = build({ type = 'Sub2', amount = 0.5, base = 'Walk', sub = 'Breathe' })
    tree:update(0.1)
    tester:check(
        tracks.Breathe.additive and tracks.Breathe.subtract and near(tracks.Breathe.weight, 0.5),
        'Sub2 removes the difference of its clip, scaled by the amount'
    )

    tree, tracks = build({
        type = 'StateMachine',
        states = { A = 'XA', B = 'XB' },
        transitions = { { from = 'A', to = 'B', expression = 'speed > 0.5 and not blocked' } },
    })
    tree:set('speed', 1)
    tree:set('blocked', true)
    tree:update(0.1)
    tester:check(tree:state() == 'A', 'A transition expression reads the parameters')
    tree:set('blocked', false)
    tree:update(0.1)
    tester:check(tree:state() == 'B', 'A transition expression fires when it holds')

    tree, tracks = build({
        type = 'OneShot',
        request = 'wave',
        fadeIn = 0.2,
        fadeOut = 0.2,
        filter = { 'Arm' },
        input = 'Walk',
        shot = { clip = 'Wave' },
    })
    tree:update(0.1)
    tester:check(tracks.Wave.weight == 0 and tracks.Walk.weight == 1, 'A OneShot stays silent until requested')
    tree:trigger('wave')
    tree:update(0.1)
    tester:check(near(tracks.Wave.weight, 0.5) and tracks.Wave.order > tracks.Walk.order, 'A OneShot fades its layer in over the input')
    tester:check(tracks.Wave.looped == false and tracks.Wave.boneMask.Arm == 1, 'A OneShot plays once and honours its filter')
    for _ = 1, 3 do
        tree:update(0.2)
    end
    tester:check(near(tracks.Wave.weight, 1), 'A OneShot holds full weight between its fades')
    for _ = 1, 4 do
        tree:update(0.2)
    end
    tester:check(tracks.Wave.weight == 0 and tracks.Walk.weight == 1, 'A OneShot ends after its clip')

    tree, tracks = build({
        type = 'Transition',
        param = 'stance',
        fade = 0.4,
        inputs = { { 'Stand', 'Idle' }, { 'Crouch', 'Duck' } },
    })
    tree:set('stance', 'Stand')
    tree:update(0.1)
    tree:set('stance', 'Crouch')
    tree:update(0.2)
    tester:check(near(tracks.Idle.weight, 0.5) and near(tracks.Duck.weight, 0.5), 'Transition crossfades to the chosen input')
    tree:set('stance', 1)
    tree:update(0.1)
    tester:check(tracks.Idle.weight > 0.5, 'Transition accepts an index and turns back mid-fade')

    tree, tracks = build({ type = 'TimeSeek', seek = 'to', child = 'Walk' })
    tree:set('to', 0.25)
    tree:update(0.1)
    tester:check(near(tracks.Walk.timePosition, 0.25) and tree:get('to') == nil, 'TimeSeek moves the clip and clears its request')

    tree, tracks = build({
        type = 'Blend2D',
        x = 'x',
        y = 'y',
        points = { { 0, 0, 'P0' }, { 1, 0, 'P1' }, { 0, 1, 'P2' }, { 1, 1, 'P3' } },
    })
    tree:set('x', 0.25)
    tree:set('y', 0.25)
    tree:update(0.1)
    tester:check(near(tracks.P0.weight, 0.5) and near(tracks.P1.weight, 0.25) and near(tracks.P2.weight, 0.25), 'Blend2D weights the triangle around the sample')
    tree:set('x', 3)
    tree:set('y', 0)
    tree:update(0.1)
    tester:check(near(tracks.P1.weight, 1), 'Blend2D clamps outside the points to the hull')

    tree, tracks = build({ type = 'Blend2D', mode = 'Discrete', x = 'x', y = 'y', points = { { 0, 0, 'D0' }, { 1, 0, 'D1' } } })
    tree:set('x', 0.8)
    tree:update(0.1)
    tester:check(tracks.D1.weight == 1 and tracks.D0.weight == 0, 'Blend2D Discrete plays the nearest clip')

    tree, tracks = build({ type = 'Blend1D', mode = 'Carry', param = 'v', points = { { 0, 'C0' }, { 1, 'C1' } } })
    tree:set('v', 0)
    tree:update(0.1)
    tracks.C0.timePosition = 0.6
    tree:set('v', 1)
    tree:update(0.1)
    tester:check(tracks.C1.weight == 1 and near(tracks.C1.timePosition, 0.6), 'Blend1D Carry keeps the phase on a switch')

    tree, tracks = build({
        type = 'StateMachine',
        start = 'A',
        fade = 0.1,
        states = { A = 'SA', B = 'SB', C = 'SC' },
        transitions = {
            { from = 'A', to = 'B', when = 'go', switch = 'AtEnd', fade = 0.1 },
            { from = 'A', to = 'C', when = 'go', priority = -1, advance = 'Disabled' },
            { from = 'B', to = 'C', fade = 0.1 },
            { from = 'C', to = 'End', when = 'stop' },
        },
    })
    tree:update(0.1)
    tree:set('go', true)
    tree:update(0.1)
    tester:check(tree:state() == 'A', 'An AtEnd transition waits while the clip is not near its end')
    tracks.SA.timePosition = 0.85
    tree:update(0.1)
    tester:check(tree:state() == 'B', 'An AtEnd transition fires when the fade would end with the clip')
    tree:set('go', nil)

    tree, tracks = build({
        type = 'StateMachine',
        start = 'A',
        fade = 0.1,
        states = { A = 'TA', B = 'TB', C = 'TC' },
        transitions = {
            { from = 'A', to = 'B', advance = 'Disabled' },
            { from = 'B', to = 'C', advance = 'Disabled' },
            { from = 'C', to = 'End', when = 'stop' },
        },
    })
    tree:update(0.1)
    tree:travel('C')
    tree:update(0.1)
    tester:check(tree:state() == 'B', 'travel walks through the states between')
    tree:update(0.1)
    tester:check(tree:state() == 'C', 'travel ends on the requested state')
    tree:set('stop', true)
    tree:update(0.1)
    tester:check(tree:state() == 'End' and tree.root:finished(), 'A machine that reaches End is finished')
end

return Tests
