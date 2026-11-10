local ipairs = require('../math.array').ipairs
local pairs = require('../math.array').pairs
local M = require('../math.math3d')
local Geometry = require('../graphics.geometry.primitives')
local Validate = require('../core.validate')
local Node = require('../nodes')
local NodeTree = require('../nodes.core.nodeTree')

local World3D = {}
World3D.__index = function(world, key)
    if key == 'debug' then
        return world.environment and world.environment.debug
    end
    return World3D[key]
end
World3D.__newindex = function(world, key, value)
    if key == 'physics' and value and value.bindDebug then
        require('source.engine.world.gravity').bind(world.root, value)
        value:bindDebug(world.environment.debug.physics)
        rawset(world, key, value)
        world.root:onDestroy(function()
            value:release()
        end)
    elseif key == 'debug' and world.environment then
        value = value or {}
        value.gizmos = value.gizmos or world.environment.debug.gizmos
        value.physics = value.physics or world.environment.debug.physics
        if world.physics then
            world.physics:bindDebug(value.physics)
        end
        world.environment.debug = value
        world.environment.gizmos = value.gizmos
    else
        rawset(world, key, value)
    end
end

function World3D.new(resources, lighting, options)
    lighting = lighting or require('source.engine.graphics.lighting.defaults').create()
    local self = setmetatable({
        resources = resources,
        lighting = lighting,
        uis = {},
        objects = {},
        byName = {},
        lights = {},
        billboards = {},
        geometry = {},
        root = Node.new(
            'World3D',
            { name = 'World3D', position = { 0, 0, 0 }, rotation = { 0, 0, 0 }, size = { 1, 1, 1 } }
        ),
        cameras = {},
        layers = { default = 1, player = 2 },
    }, World3D)
    self.animations = require('source.engine.animation.scheduler').new()
    self.shaderLayers = require('source.engine.graphics.shaders.layers').new(function(registry, info)
        -- Renames and removals reach every shader node of this world, like layer groups.
        if not info or not self.root then
            return
        end
        for _, node in ipairs(self.root:getDescendants()) do
            if node.shaderLayer and (node._world or node._sceneWorld) == self then
                if info.renamed and node.shaderLayer == info.renamed[1] then
                    node.shaderLayer = info.renamed[2]
                elseif info.removed and node.shaderLayer == info.removed then
                    node.shaderLayer = node:isA('Shader2D') and 'Default2D' or 'Default3D'
                end
            end
        end
    end)
    self:initializeLayerGroups()
    self.root._world = self
    self.root._sceneWorld = self
    Node.create('Environment', lighting, self.root, self)
    self.prefabs = require('source.engine.core.prefabs').new(self)
    self.decals = {}
    self.directionalLights = {}
    self.surfaceQuad = Geometry.quad()
    resources:own(self.surfaceQuad.mesh)
    -- Historical category names (`folders.Geometry`, `folders.Lights` ...) all resolve to the world
    -- root: nodes live directly under the World, exactly as the scene composes them, and the
    -- Explorer shows no organizational folders.
    self.folders = setmetatable({}, {
        __index = function()
            return self.root
        end,
    })
    self.root._world = self
    self.nodeTree = NodeTree.new(self.root)
    self.root._nodeTree = self.nodeTree
    self.geometry.cube = Geometry.cube()
    self.geometry.plane = Geometry.plane()
    resources:own(self.geometry.cube.mesh)
    resources:own(self.geometry.plane.mesh)
    if options and options.physics then
        self:createPhysics(options.physics)
    end
    return self
end

function World3D:createPhysics(settings)
    assert(not self.physics, 'World physics is already configured')
    self.physics = require('source.engine.physics').new(settings)
    return self.physics
end

function World3D:addLayer(name)
    return self.layerGroups:add(name)
end

function World3D:setLayerVisible(camera, name, enabled)
    self:resolveLayerGroup(camera)
    self.layerGroups:add(name)
    self.layerGroups:set(camera.layerGroup, name, enabled)
end

function World3D:updateCameras(dt)
    local camera = self.activeCamera
    if not camera or camera.followMode == 'Free' then
        return
    end
    if not camera._controller then
        local name = camera.followTarget
        local target
        for _, node in ipairs(self.root:getDescendants()) do
            if node.name == name and node.getWorldMatrix then
                target = node
                break
            end
        end
        require('source.engine.cameras.controller').new(camera, {
            target = target,
            mode = camera.followMode,
            physics = self.physics,
            distance = camera.followDistance,
            sensitivity = camera.followSensitivity,
            positionSmooth = camera.followSmooth,
            minPitch = camera.pitchMin,
            maxPitch = camera.pitchMax,
        })
        camera.followTarget = name
    end
    camera._controller:update(dt)
end

function World3D:create(className, properties, parent)
    className = Node.aliases[className] or className
    properties = properties or {}
    if className == 'World2D' or className == 'Environment' or className == 'Shader3D' then
        parent = parent or self.root
    end
    local category = ({
        Mesh3D = 'Geometry',
        Camera3D = 'Cameras',
        PointLight3D = 'Lights',
        SpotLight3D = 'Lights',
        DirectionalLight3D = 'Lights',
        BillboardUI = 'Billboards',
        Body3D = 'Physics',
        ParticleEmitter3D = 'Effects',
        Beam3D = 'Effects',
        Trail3D = 'Effects',
        SoundGroup = 'Audio',
        Sound = 'Audio',
    })[className]
    local class = Node.getClass(className, self)
    local constraintClass = class
    while constraintClass do
        if constraintClass.name == 'Constraint3D' then
            category = 'Physics'
            break
        end
        constraintClass = constraintClass.base
    end
    local c = class
    local context = self
    if class._types.Node2D or class._types.Constraint2D then
        local owner = parent
        while owner and not owner:isA('World2D') do
            owner = owner.parent
        end
        context = owner or self.uis[1]
        assert(context, '2D spatial nodes require World2D')
        parent = parent or context
    end
    while c do
        if c.name == 'UINode' then
            context = parent and (parent.ui or parent._plane or parent:isA('World2D') and parent)
                or self.uis[1]
            assert(context, 'UI nodes require World2D')
            parent = parent or context.content
            break
        end
        c = c.base
    end
    local node =
        Node.create(className, properties, parent or self.folders[category or 'Scripts'], context)
    if node._class.registrationWorld and node._class.scriptUpdate then
        node:setProcess(true)
    end
    return node
end

function World3D:loadModel(path, settings)
    local Models = require('source.engine.import.models')
    local model = Models.load(path, self.resources)
    local objects, root = Models.instantiate(self, model, settings)
    return root, model, objects
end

function World3D:registerNodeType(name, definition)
    return require('source.engine.nodes.core.specialNode').register(self, name, definition)
end

function World3D:setInteractionSource(node)
    assert(
        node == nil
            or node._node
                and node:isA('Node3D')
                and not node.destroyed
                and (node._world or node._sceneWorld) == self,
        'Interaction source must be a live Node3D in this World3D'
    )
    self.interactionSource = node
end

function World3D:setQualityProfile(name)
    local profile = assert(
        require('source.engine.graphics.quality.qualityProfiles')[name],
        'Unknown quality profile'
    )
    for key, value in pairs(profile.shadows) do
        self.lighting.shadows[key] = value
    end
    for key, value in pairs(profile.lights) do
        self.lighting.lightSettings[key] = value
    end
    self.ribbonDetail = profile.ribbons and profile.ribbons.detail or 1
    self.qualityProfile = name
end

function World3D:updateNodes(dt)
    self.simulationTime = (self.simulationTime or 0) + dt
    self.animations:update(dt)
    self.nodeTree:update(dt)
    for _, controller in ipairs(self.rigidControllers or {}) do
        controller:update(dt)
    end
    if self.particles then
        self.particles:update(dt)
    end
    require('source.engine.graphics.geometry.blendShapes').flushQueue(self)
end

function World3D:invalidateRender()
    self._renderInvalidationRevision = (self._renderInvalidationRevision or 0) + 1
end

function World3D:release()
    self.animations:release()
    local ok, message = pcall(self.root.destroy, self.root)
    self.nodeTree:release()
    self.nodeTypes, self.interactionSource = {}, nil
    if not ok then
        error(message, 0)
    end
end

function World3D:addLight(l)
    assert(not l._world or l._world == self, 'Light belongs to another World3D')
    l._world = self
    Node.adopt(l, l.className or l.type or 'PointLight3D')
    l._world = self
    l.parent = l.parent or self.folders.Lights
    l.worldPosition = {}
    l.worldDirection = {}
    l:onDestroy(function()
        self:removeLight(l)
    end)
    l.type = l.type or 'PointLight3D'
    assert(
        l.type == 'PointLight3D' or l.type == 'SpotLight3D' or l.type == 'DirectionalLight3D',
        'Unknown light type'
    )
    l.position = l.position or { 0, 0, 0 }
    local omitted = require('source.engine.nodes.core.classPolicy').omitted(l._class)
    if omitted.rotation then
        l.rotation = nil -- a point light has no direction; creation input naming one is ignored
    else
        l.rotation = l.rotation or { 0, 0, 0 }
    end
    l.color = l.color or { 255, 255, 255 }
    l.range = l.range or 100
    l.radius = l.radius or 5
    -- How much of the volumetric fog this light burns away where it shines (fog lamps).
    l.fogClearing = l.fogClearing or 0.5
    require('source.engine.components.rendering.brightness').normalize(l, 3, 'Light')
    l.enabled = l.enabled ~= false
    Validate.vector(l.position, 'Light.position', 3)
    if not omitted.rotation then
        Validate.vector(l.rotation, 'Light.rotation', 3)
    end
    Validate.vector(l.color, 'Light.color', 3)
    Validate.number(l.range, 'Light.range', 0.001)
    Validate.number(l.radius, 'Light.radius', 0)
    Validate.number(l.fogClearing, 'Light.fogClearing', 0, 1)
    self.lights[#self.lights + 1] = l
    return l
end
-- Picking occurs only on a press, never as per-frame CPU triangle rendering.
function World3D:occluded(camera, x, y, distance)
    local p, ray = camera:screenRay(x, y)
    local wx, wy, wz = ray[1], ray[2], ray[3]
    local a, b, c = {}, {}, {}
    for _, o in ipairs(self.objects) do
        if
            o:isVisible()
            and o.transparency < 1
            and (o.color[4] or 1) > 0
            and camera:visible(o.worldPosition or o.position, o.radius)
        then
            local m = o.combined or o.matrix
            local vertices = o.geometry.vertices
            for i = 1, #vertices, 3 do
                for j, target in ipairs({ a, b, c }) do
                    local v = vertices[i + j - 1]
                    target[1], target[2], target[3] = M.transform(m, v[1], v[2], v[3])
                end
                local ex, ey, ez = b[1] - a[1], b[2] - a[2], b[3] - a[3]
                local fx, fy, fz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
                local facing = (ey * fz - ez * fy) * wx
                    + (ez * fx - ex * fz) * wy
                    + (ex * fy - ey * fx) * wz
                local t = (o.doubleSided or facing < 0)
                    and M.rayTriangle(p[1], p[2], p[3], wx, wy, wz, a, b, c)
                if t and t < distance - 0.001 then
                    return true
                end
            end
        end
    end
    return false
end

function World3D:removeObject(name)
    local object = self.byName[name]
    if object and not object.destroyed then
        object:destroy()
        return
    end
    if not object then
        return
    end
    for i, o in ipairs(self.objects) do
        if o == object then
            table.remove(self.objects, i)
            break
        end
    end
    self.byName[name] = nil
end

function World3D:removeLight(light)
    if not light.destroyed then
        light:destroy()
        return
    end
    light.enabled = false
    for i, item in ipairs(self.lights) do
        if item == light then
            table.remove(self.lights, i)
            break
        end
    end
end

function World3D:removeBillboard(billboard)
    if not billboard.destroyed then
        billboard:destroy()
        return
    end
    billboard.enabled = false
    for i, item in ipairs(self.billboards) do
        if item == billboard then
            table.remove(self.billboards, i)
            break
        end
    end
    self.resources:releaseOwned(billboard.canvas)
end
require('./objects').install(World3D)
require('./cameras').install(World3D)
require('./layerGroups').install(World3D)
return World3D
