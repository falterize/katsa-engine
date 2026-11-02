-- IK plugin: quaternion helpers, bone pose access, the four solvers, influence blending,
-- modifier ordering and the Animator hook (fake rigs for exact maths, xbot for integration).
local Quat = require('source.plugins.ik.quat')
local IK = require('source.engine.plugins').require('ik')

local Module = {}

local function near(a, b, tolerance)
    return math.abs(a - b) <= (tolerance or 1e-4)
end

local function distance(ax, ay, az, bx, by, bz)
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2)
end

-- A straight chain of `count` bones, `length` apart along -Y, parented in order. The model root
-- is translated by (10, 0, 0) and uniformly scaled by 2 to exercise the world<->model mapping.
local function chain(count, length)
    local model = { nodes = {}, byNodeName = {}, roots = { 0 } }
    for i = 1, count do
        local node = {
            name = 'B' .. i,
            index = i,
            translation = { 0, i == 1 and 0 or -(length or 1), 0 },
            rotation = { 0, 0, 0, 1 },
            scale = { 1, 1, 1 },
            children = {},
            isBone = true,
        }
        node.parent = model.nodes[i - 1]
        model.nodes[i] = node
        model.byNodeName[node.name] = node
    end
    local root = { 2, 0, 0, 10, 0, 2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 1 }
    model.root = {
        getWorldMatrix = function()
            return root
        end,
    }
    return model
end

local function fakeAnimator(model)
    local Class = require('source.engine.nodes').getClass('Animator')
    return setmetatable({ model = model, modifiers = {}, _poseStep = 1 / 60 }, { __index = Class })
end

local function worldOf(x, y, z)
    return 10 + 2 * x, 2 * y, 2 * z
end

local function run(animator)
    for _, modifier in ipairs(animator.modifiers) do
        modifier:process(animator, 1 / 60)
    end
end

function Module.run(self)
    -- Quaternion maths.
    local q = Quat.fromTo(1, 0, 0, 0, 1, 0)
    local x, y, z = Quat.rotate(q, 1, 0, 0)
    self:check(near(x, 0) and near(y, 1) and near(z, 0), 'fromTo rotates a onto b')
    q = Quat.fromTo(0, 1, 0, 0, -1, 0)
    x, y, z = Quat.rotate(q, 0, 1, 0)
    self:check(near(y, -1) and near(Quat.angle(q), math.pi), 'fromTo handles opposite directions')
    local product = Quat.multiply(Quat.axisAngle(0, 0, 1, 0.3), Quat.axisAngle(0, 0, 1, 0.4))
    self:check(near(Quat.angle(product), 0.7), 'quaternion product adds rotations about one axis')
    local half = Quat.scale(Quat.axisAngle(0, 1, 0, 1.0), 0.5)
    self:check(near(Quat.angle(half), 0.5), 'scale takes a fraction of a rotation')

    -- Skeleton pose access.
    local model = chain(3)
    local skeleton = IK.Skeleton.new(model)
    local px, py, pz = skeleton:getPosition('B3')
    self:check(near(px, 0) and near(py, -2) and near(pz, 0), 'global position follows the chain')
    skeleton:rotate('B1', Quat.axisAngle(0, 0, 1, math.pi / 2))
    px, py, pz = skeleton:getPosition('B3')
    self:check(near(px, 2) and near(py, 0), 'rotating a bone moves its descendants')
    self:check(near(Quat.angle(skeleton:getRotation('B3')), math.pi / 2), 'global rotation inherits parents')
    local wx, wy, wz = skeleton:toWorld(0.5, -1, 0.25)
    local mx, my, mz = skeleton:toModel(wx, wy, wz)
    self:check(near(wx, 11) and near(mx, 0.5) and near(my, -1) and near(mz, 0.25), 'world/model mapping round-trips')

    -- TwoBone.
    model = chain(3)
    local animator = fakeAnimator(model)
    local tx, ty, tz = 0.6, -1.3, 0.4
    local leg = IK.TwoBone.new({
        root = 'B1',
        mid = 'B2',
        tip = 'B3',
        target = { worldOf(tx, ty, tz) },
        pole = { worldOf(0, -1, 5) },
    })
    leg:attach(animator)
    run(animator)
    skeleton = IK.Skeleton.new(model)
    local cx, cy, cz = skeleton:getPosition('B3')
    self:check(distance(cx, cy, cz, tx, ty, tz) < 1e-4, 'TwoBone reaches a reachable target')
    local bx, by, bz = skeleton:getPosition('B2')
    self:check(
        near(distance(0, 0, 0, bx, by, bz), 1) and near(distance(bx, by, bz, cx, cy, cz), 1),
        'TwoBone preserves bone lengths'
    )
    self:check(bz > 0.1, 'TwoBone bends toward the pole')
    leg.pole = { worldOf(0, -1, -5) }
    model.nodes[1].rotation, model.nodes[2].rotation = { 0, 0, 0, 1 }, { 0, 0, 0, 1 }
    run(animator)
    skeleton = IK.Skeleton.new(model)
    bx, by, bz = skeleton:getPosition('B2')
    self:check(bz < -0.1, 'moving the pole flips the bend')
    leg.target = { worldOf(0, -9, 0) }
    model.nodes[1].rotation, model.nodes[2].rotation = { 0, 0, 0, 1 }, { 0, 0, 0, 1 }
    run(animator)
    skeleton = IK.Skeleton.new(model)
    cx, cy, cz = skeleton:getPosition('B3')
    self:check(cy < -1.99 and near(cx, 0, 1e-3), 'TwoBone stretches straight toward an unreachable target')

    -- Influence blending halves the rotation of the root bone.
    model = chain(3)
    animator = fakeAnimator(model)
    local full = IK.TwoBone.new({ root = 'B1', mid = 'B2', tip = 'B3', target = { worldOf(1.2, -0.9, 0) } })
    full:attach(animator)
    run(animator)
    local fullAngle = Quat.angle(model.nodes[1].rotation)
    model.nodes[1].rotation, model.nodes[2].rotation = { 0, 0, 0, 1 }, { 0, 0, 0, 1 }
    full.influence = 0.5
    run(animator)
    self:check(
        fullAngle > 0.1 and near(Quat.angle(model.nodes[1].rotation), fullAngle * 0.5, 1e-3),
        'influence 0.5 applies half of the solved rotation'
    )
    model.nodes[1].rotation, model.nodes[2].rotation = { 0, 0, 0, 1 }, { 0, 0, 0, 1 }
    full.influence = 0
    run(animator)
    self:check(Quat.angle(model.nodes[1].rotation) == 0, 'influence 0 leaves the animated pose untouched')

    -- Animator registration and ordering.
    animator = fakeAnimator(model)
    local order = {}
    local function probe(name, priority)
        return { priority = priority, process = function() order[#order + 1] = name end }
    end
    local late, early = probe('late', 5), probe('early', -5)
    animator:addModifier(late)
    animator:addModifier(early)
    animator:addModifier(early)
    run(animator)
    self:check(#animator.modifiers == 2 and order[1] == 'early' and order[2] == 'late', 'modifiers run by priority, once each')
    self:check(animator:removeModifier(early) and early.animator == nil and #animator.modifiers == 1, 'modifiers can be removed')

    -- LookAt: chain with weights and an angle limit.
    model = chain(3)
    animator = fakeAnimator(model)
    local look = IK.LookAt.new({
        bones = { 'B1', 'B2' },
        weights = { 1, 1 },
        forward = { 0, 0, 1 },
        target = { worldOf(5, 0, 5) },
    })
    look:attach(animator)
    run(animator)
    skeleton = IK.Skeleton.new(model)
    local rx, ry, rz = Quat.rotate(skeleton:getRotation('B2'), 0, 0, 1)
    local length = math.sqrt(rx * rx + rz * rz)
    self:check(near(ry, 0, 1e-3) and near(rx / length, 0.7071, 1e-3), 'LookAt turns the chain toward the target')
    model = chain(3)
    animator = fakeAnimator(model)
    look = IK.LookAt.new({ bone = 'B1', forward = { 0, 0, 1 }, maxAngle = 30, target = { worldOf(5, 0, 0) } })
    look:attach(animator)
    run(animator)
    local angle = Quat.angle(model.nodes[1].rotation)
    self:check(near(angle, math.rad(30), 1e-3), 'LookAt maxAngle limits the turn')

    -- FABRIK and CCD on a four-bone chain.
    for _, solver in ipairs({ 'Fabrik', 'Ccd' }) do
        model = chain(4)
        animator = fakeAnimator(model)
        local goal = { 0.8, -1.4, 0.9 }
        local modifier = IK[solver].new({
            bones = { 'B1', 'B2', 'B3', 'B4' },
            target = { worldOf(goal[1], goal[2], goal[3]) },
            iterations = 40,
            tolerance = 1e-4,
        })
        modifier:attach(animator)
        run(animator)
        skeleton = IK.Skeleton.new(model)
        local ex, ey, ez = skeleton:getPosition('B4')
        self:check(distance(ex, ey, ez, goal[1], goal[2], goal[3]) < 0.01, solver .. ' reaches a reachable target')
        local ax, ay, az = skeleton:getPosition('B1')
        self:check(near(ax, 0) and near(ay, 0) and near(az, 0), solver .. ' keeps the root pinned')
        local b2x, b2y, b2z = skeleton:getPosition('B2')
        self:check(near(distance(ax, ay, az, b2x, b2y, b2z), 1, 1e-3), solver .. ' preserves bone lengths')
    end
    model = chain(4)
    animator = fakeAnimator(model)
    IK.Fabrik.new({ bones = { 'B1', 'B2', 'B3', 'B4' }, target = { worldOf(0, -20, 0) } }):attach(animator)
    run(animator)
    skeleton = IK.Skeleton.new(model)
    local _, farY = skeleton:getPosition('B4')
    self:check(near(farY, -3, 1e-3), 'Fabrik straightens toward an unreachable target')
    model = chain(4)
    animator = fakeAnimator(model)
    IK.Ccd.new({
        bones = { 'B1', 'B2', 'B3', 'B4' },
        target = { worldOf(3, 0, 0) },
        iterations = 30,
        limits = { B1 = 10, B2 = 10, B3 = 10 },
    }):attach(animator)
    run(animator)
    local within = true
    for i = 1, 3 do
        within = within and Quat.angle(model.nodes[i].rotation) <= math.rad(10) + 1e-3
    end
    self:check(within, 'Ccd limits cap how far a joint leaves the animated pose')

    -- Integration: the real Animator hook on a skinned model.
    local Models = require('source.engine.import.models')
    local resources = self.manager.resources:scope()
    local world = require('source.engine.world.world').new(resources)
    local xbot = Models.load('assets/models/characters/xbot.glb', resources)
    Models.instantiate(world, xbot, { name = 'IKProbe', position = { 3, 0, 4 } })
    local hand = 'mixamorig:RightHand'
    local arm = IK.TwoBone.new({
        root = 'mixamorig:RightArm',
        mid = 'mixamorig:RightForeArm',
        tip = hand,
    })
    local live = IK.Skeleton.new(xbot)
    local sx, sy, sz = live:getPosition('mixamorig:RightArm')
    local hx0, hy0, hz0 = live:getPosition(hand)
    local reach = distance(sx, sy, sz, hx0, hy0, hz0)
    -- A point 0.75 of the arm's reach away from the shoulder, in model space.
    arm.target = { live:toWorld(sx + 0.5 * reach, sy - 0.4 * reach, sz + 0.3 * reach) }
    arm:attach(xbot.animator)
    xbot.animator.poseRate = 240
    for _ = 1, 3 do
        xbot.animator:update(1 / 60)
    end
    live:refresh()
    local hx, hy, hz = live:getPosition(hand)
    local hwx, hwy, hwz = live:toWorld(hx, hy, hz)
    -- World distance tolerance: 1% of the reach, scaled by the model root.
    local scale
    local ox, oy, oz = live:toWorld(0, 0, 0)
    local ux, uy, uz = live:toWorld(1, 0, 0)
    scale = distance(ox, oy, oz, ux, uy, uz)
    self:check(
        distance(hwx, hwy, hwz, arm.target[1], arm.target[2], arm.target[3]) < 0.01 * reach * scale,
        'TwoBone drives the xbot hand onto a world target through Animator:update'
    )
    local node = xbot.byNodeName[hand]
    self:check(
        near(node.world[4], hx, 1e-3) and near(node.world[8], hy, 1e-3),
        'the pose matrices include the IK edit'
    )
end

return Module
