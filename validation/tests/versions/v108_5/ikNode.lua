-- InverseKinematics3D node: type-dependent inspector fields, bone lists, solving through the
-- model's Animator, plus the Jacobian, Spline and FK solvers on exact fake rigs.
local IK = require('source.engine.plugins').require('ik')
local Quat = require('source.plugins.ik.quat')
local Schema = require('source.engine.editor.inspectors.schema')

local Module = {}

local function near(a, b, tolerance)
    return math.abs(a - b) <= (tolerance or 1e-4)
end

local function distance(ax, ay, az, bx, by, bz)
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2)
end

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
        node.rest = { rotation = { 0, 0, 0, 1 } }
        node.parent = model.nodes[i - 1]
        model.nodes[i] = node
        model.byNodeName[node.name] = node
    end
    local root = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
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

local function run(animator)
    for _, modifier in ipairs(animator.modifiers) do
        modifier:process(animator, 1 / 60)
    end
end

function Module.run(self)
    -- Jacobian reaches a target and keeps the root pinned and the lengths intact.
    local model = chain(4)
    local animator = fakeAnimator(model)
    IK.Jacobian.new({
        bones = { 'B1', 'B2', 'B3', 'B4' },
        target = { 0.9, -1.2, 1.1 },
        iterations = 60,
        tolerance = 1e-3,
        maxStep = 15,
    }):attach(animator)
    run(animator)
    local skeleton = IK.Skeleton.new(model)
    local x, y, z = skeleton:getPosition('B4')
    self:check(distance(x, y, z, 0.9, -1.2, 1.1) < 0.02, 'Jacobian reaches a reachable target')
    local rx, ry, rz = skeleton:getPosition('B1')
    local bx, by, bz = skeleton:getPosition('B2')
    self:check(near(rx, 0) and near(ry, 0) and near(distance(rx, ry, rz, bx, by, bz), 1, 1e-3), 'Jacobian keeps root and lengths')

    -- Spline: the chain lies on a straight curve along +X.
    model = chain(4)
    animator = fakeAnimator(model)
    IK.Spline.new({
        bones = { 'B1', 'B2', 'B3', 'B4' },
        points = { { 0, 0, 0 }, { 1, 0, 0 }, { 2, 0, 0 }, { 5, 0, 0 } },
    }):attach(animator)
    run(animator)
    skeleton = IK.Skeleton.new(model)
    x, y, z = skeleton:getPosition('B4')
    self:check(near(x, 3, 1e-3) and near(y, 0, 1e-3) and near(z, 0, 1e-3), 'Spline lays the chain along the curve')
    model = chain(3)
    animator = fakeAnimator(model)
    IK.Spline.new({
        bones = { 'B1', 'B2', 'B3' },
        points = function()
            return { { 0, 0, 0 }, { 0, -1, 1 }, { 0, -2, 3 }, { 0, -2, 6 } }
        end,
    }):attach(animator)
    run(animator)
    skeleton = IK.Skeleton.new(model)
    x, y, z = skeleton:getPosition('B3')
    local mx, my, mz = skeleton:getPosition('B2')
    self:check(
        near(distance(0, 0, 0, mx, my, mz), 1, 1e-3) and z > 1.3 and near(x, 0, 1e-3),
        'Spline bends the chain with the curve and keeps bone lengths'
    )

    -- FK: additive curl with falloff, rest-based mode, named pose.
    model = chain(3)
    animator = fakeAnimator(model)
    local fk = IK.FK.new({ bones = { 'B1', 'B2' }, rotation = { 40, 0, 0 }, falloff = 0.5 })
    fk:attach(animator)
    run(animator)
    self:check(
        near(Quat.angle(model.nodes[1].rotation), math.rad(40), 1e-4)
            and near(Quat.angle(model.nodes[2].rotation), math.rad(20), 1e-4),
        'FK turns each bone by its share of the rotation'
    )
    run(animator)
    self:check(Quat.angle(model.nodes[1].rotation) > math.rad(79), 'FK Additive stacks on the current pose')
    model.nodes[1].rest.rotation = { 0, 0, 0, 1 }
    fk.mode = 'FromRest'
    run(animator)
    self:check(near(Quat.angle(model.nodes[1].rotation), math.rad(40), 1e-4), 'FK FromRest ignores the animated pose')
    model = chain(2)
    animator = fakeAnimator(model)
    IK.FK.new({ pose = { B2 = { 0, 90, 0 } } }):attach(animator)
    run(animator)
    self:check(near(Quat.angle(model.nodes[2].rotation), math.pi / 2, 1e-4), 'FK pose table turns named bones')

    -- Skeleton.chain.
    model = chain(4)
    skeleton = IK.Skeleton.new(model)
    local names = skeleton:chain('B2', 'B4')
    self:check(#names == 3 and names[1] == 'B2' and names[3] == 'B4', 'Skeleton:chain lists bones root to tip')

    -- The node: registration, type dependent fields and solving through the real Animator.
    local Plugins = require('source.engine.plugins')
    local Models = require('source.engine.import.models')
    local resources = self.manager.resources:scope()
    local world = require('source.engine.world.world').new(resources)
    Plugins.activate(world, { 'ik' })
    local xbot = Models.load('assets/models/characters/xbot.glb', resources)
    local _, root = Models.instantiate(world, xbot, { name = 'IKNodeBot', position = { 1, 0, 2 } })
    local ball = world:create('Node3D', { name = 'IKBall', position = { 0, 0, 0 } })
    local live = IK.Skeleton.new(xbot)
    local sx, sy, sz = live:getPosition('mixamorig:RightArm')
    local hx0, hy0, hz0 = live:getPosition('mixamorig:RightHand')
    local reach = distance(sx, sy, sz, hx0, hy0, hz0)
    local wx, wy, wz = live:toWorld(sx + 0.5 * reach, sy - 0.4 * reach, sz + 0.3 * reach)
    ball.position = { wx, wy, wz }
    local node = world:create('InverseKinematics3D', {
        type = 'TwoBone',
        tipBone = 'mixamorig:RightHand',
        target = ball,
    }, root)
    self:check(node:isA('Node3D') and node.type == 'TwoBone' and node.influence == 1, 'node defaults come from the property descriptors')
    local function visible(target, key)
        return Schema.visible(target, key)
    end
    self:check(visible(node, 'pole') and visible(node, 'softness') and not visible(node, 'damping'), 'TwoBone shows pole and softness only')
    node.type = 'Jacobian'
    self:check(visible(node, 'damping') and visible(node, 'maxStep') and not visible(node, 'pole'), 'Jacobian shows damping and step')
    node.type = 'LookAt'
    self:check(visible(node, 'forward') and visible(node, 'maxAngle') and not visible(node, 'iterations'), 'LookAt shows forward and angle limit')
    node.type = 'FK'
    self:check(visible(node, 'rotation') and not visible(node, 'target'), 'FK hides the target')
    node.type = 'Spline'
    self:check(visible(node, 'splineOffset') and not visible(node, 'target'), 'Spline shows the offset')
    local options = Schema.options(node, 'tipBone')
    self:check(options and #options > 20, 'bone fields list the bones of the model')
    self:check(Schema.options(node, 'type')[1] == 'TwoBone', 'type offers the solver list')
    node.type = 'TwoBone'
    xbot.animator.poseRate = 240
    for _ = 1, 3 do
        world:updateNodes(1 / 60)
        xbot.animator:update(1 / 60)
    end
    self:check(node.animator == xbot.animator, 'the node registers with the model animator')
    live:refresh()
    local hx, hy, hz = live:getPosition('mixamorig:RightHand')
    local hwx, hwy, hwz = live:toWorld(hx, hy, hz)
    local ox, oy, oz = live:toWorld(0, 0, 0)
    local ux, uy, uz = live:toWorld(1, 0, 0)
    local scale = distance(ox, oy, oz, ux, uy, uz)
    self:check(distance(hwx, hwy, hwz, wx, wy, wz) < 0.01 * reach * scale, 'the node drives the hand onto its target')
    node.influence = 0
    xbot.animator:update(1 / 60)
    xbot.animator:update(1 / 60)
    live:refresh()
    local rx0, ry0, rz0 = live:getPosition('mixamorig:RightHand')
    self:check(distance(rx0, ry0, rz0, hx0, hy0, hz0) < 1e-3 * reach, 'influence 0 restores the animation')
    node:destroy()
    self:check(#xbot.animator.modifiers == 0, 'destroying the node unregisters it')
end

return Module
