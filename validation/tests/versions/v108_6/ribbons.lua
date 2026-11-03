-- Beam3D and Trail3D: geometry, trail history, modes, inspector fields and shadow proxies.
local Geometry = require('source.engine.ribbons.geometry')
local References = require('source.engine.editor.inspectors.nodeReferences')
local Schema = require('source.engine.editor.inspectors.schema')
local World = require('source.engine.world.world')

local Module = {}

local function camera()
    return {
        layers = -1,
        worldPosition = { 0, 0, 10 },
        position = { 0, 0, 10 },
        forward = { 0, 0, -1 },
        visible = function()
            return true
        end,
    }
end

local function advance(world, dt)
    world.simulationTime = (world.simulationTime or 0) + dt
end

function Module.run(self)
    -- Geometry on a straight ribbon facing the camera.
    local points = {}
    local length = Geometry.curve(points, { 0, 0, 0 }, { 0, 0, 0 }, { 10, 0, 0 }, { 10, 0, 0 }, 4, 2, 4)
    self:check(#points == 5 and math.abs(length - 10) < 1e-6, 'a straight curve keeps its length')
    self:check(math.abs(points[3].width - 3) < 1e-6, 'width interpolates between the two ends')
    for _, p in ipairs(points) do
        p.r, p.g, p.b, p.a = 1, 1, 1, 1
    end
    local vertices = {}
    local count = Geometry.strip(points, #points, {
        faceCamera = true,
        camera = { 5, 0, 10 },
        u0 = 0, v0 = 0, uw = 1, vh = 1, uOffset = 0, uScale = 0.1,
    }, vertices)
    self:check(count == 24, 'four segments make 24 vertices')
    self:check(math.abs(math.abs(vertices[1][2] - vertices[2][2]) - 2) < 1e-6, 'the camera facing strip is as wide as the first point')

    local resources = self.manager.resources:scope()
    local world = World.new(resources)
    local a0 = world:create('Node3D', { name = 'A0', position = { 0, 0, 0 } })
    local a1 = world:create('Node3D', { name = 'A1', position = { 10, 0, 0 } })
    local beam = world:create('Beam3D', { attachment0 = a0, attachment1 = a1, segments = 6 })
    local list = {}
    world.ribbons:prepare(camera(), list)
    self:check(#list == 1 and beam._count == 7, 'a beam between two plain Node3D nodes is drawn')
    self:check(math.abs(beam._length - 10) < 1e-4, 'the beam spans both nodes')
    beam.enabled = false
    list = {}
    world.ribbons:prepare(camera(), list)
    self:check(#list == 0, 'a disabled beam is skipped')
    beam.enabled = true
    beam.attachment1 = nil
    list = {}
    world.ribbons:prepare(camera(), list)
    self:check(#list == 0, 'a beam without an end draws nothing')

    -- Trail3D, Single mode: one node, history, lifetime, break distance, clear.
    local mover = world:create('Node3D', { name = 'Mover', position = { 0, 0, 0 } })
    local trail = world:create('Trail3D', {
        attachment0 = mover,
        lifetime = 1,
        minLength = 0.5,
        breakDistance = 20,
    })
    self:check(trail.trailMode == 'Single', 'Trail3D defaults to Single mode')
    for i = 1, 8 do
        mover.position = { i, 0, 0 }
        advance(world, 0.05)
        world.ribbons:prepare(camera(), {})
    end
    local stored = trail._trail.size
    self:check(stored >= 7 and trail._count >= 8, 'a moving node stores a trail')
    advance(world, 2)
    world.ribbons:prepare(camera(), {})
    self:check(trail._trail.size == 1, 'points older than lifetime expire')
    mover.position = { 100, 0, 0 }
    advance(world, 0.05)
    world.ribbons:prepare(camera(), {})
    self:check(trail._trail.size == 1, 'a teleport clears the old trail')
    trail:clear()
    self:check(trail._trail.size == 0, 'clear removes every point')
    trail.maxLength = 3
    for i = 1, 20 do
        mover.position = { 100 + i, 0, 0 }
        advance(world, 0.01)
        world.ribbons:prepare(camera(), {})
    end
    self:check(trail._length <= 3.5, 'maxLength cuts the trail')

    -- Dual mode needs two nodes; they mark the edges.
    local top = world:create('Node3D', { name = 'Top', position = { 0, 1, 0 } })
    local bottom = world:create('Node3D', { name = 'Bottom', position = { 0, -1, 0 } })
    local dual = world:create('Trail3D', { trailMode = 'Dual', attachment0 = top, minLength = 0.2 })
    advance(world, 0.1)
    world.ribbons:prepare(camera(), {})
    self:check(dual._count == 0, 'Dual mode with one node draws nothing')
    dual.attachment1 = bottom
    for i = 1, 4 do
        top.position = { i, 1, 0 }
        bottom.position = { i, -1, 0 }
        advance(world, 0.05)
        world.ribbons:prepare(camera(), {})
    end
    self:check(dual._count >= 4 and math.abs(dual._points[1].width - 2) < 1e-4, 'Dual width is the distance between its nodes')

    -- Inspector: modes, references, image configuration.
    self:check(Schema.visible(trail, 'width') and not Schema.visible(trail, 'attachment1'), 'Single shows width, hides the second node')
    self:check(Schema.visible(dual, 'attachment1') and not Schema.visible(dual, 'width'), 'Dual shows the second node, hides width')
    self:check(References.expected(trail, 'attachment0') == 'Node3D', 'ribbon ends accept any Node3D')
    self:check(References.accepts(trail, 'attachment0', mover), 'a plain Node3D is a valid ribbon end')
    local options = Schema.descriptor(trail, 'imageMode').options
    self:check(options and #options == 5, 'ribbons use the shared image modes')
    self:check(trail.texture ~= '' and trail.pixelate == false, 'ribbons carry the shared texture and pixelate settings')
    self:check(trail.lifetimeRamp ~= nil and trail.lifetimeRamp.bindings.width ~= nil, 'ribbons own a RibbonRamp')

    -- Quality profiles thin ribbons instead of removing them.
    beam.attachment1 = a1
    world:setQualityProfile('Low')
    list = {}
    world.ribbons:prepare(camera(), list)
    self:check(beam._count == 4 and #list >= 1, 'the Low profile halves the beam segments')
    world:setQualityProfile('High')

    -- Shadows: one shared component for ribbons and particles.
    local Schema2 = Schema
    self:check(Schema2.visible(beam, 'receiveShadow') and Schema2.visible(trail, 'receiveShadow'), 'receiveShadow is always listed, lit or not')
    self:check(not Schema2.visible(beam, 'shadowAlphaCutoff'), 'shadowAlphaCutoff only shows while the node casts shadows')
    world.environment.shadows.enabled = true
    beam.attachment1 = a1
    beam.castShadow = true
    world.ribbons:prepare(camera(), {})
    local output = require('source.engine.ribbons.shadows').prepare(world, camera(), {})
    self:check(#output == 1 and output[1]._particleCaster and output[1].castShadow, 'a casting beam adds a shadow proxy')
    beam.castShadow = false
    output = require('source.engine.ribbons.shadows').prepare(world, camera(), {})
    self:check(#output == 0, 'a beam that neither casts nor receives adds none')
    beam.receiveShadow, beam.lightInfluence = true, 1
    output = require('source.engine.ribbons.shadows').prepare(world, camera(), {})
    self:check(#output == 1 and output[1].receiveShadow, 'a receiving beam is a receiver proxy')

    local emitter = world:create('ParticleEmitter3D', {})
    self:check(emitter.shadowAlphaCutoff == beam.shadowAlphaCutoff, 'particles and ribbons share the shadow defaults')
    self:check(Schema.descriptor(emitter, 'shadowAlphaCutoff').hint == Schema.descriptor(beam, 'shadowAlphaCutoff').hint, 'particles and ribbons share the shadow hints')
    self:check(emitter.castShadow == false and emitter.receiveShadow == false, 'particles keep castShadow and receiveShadow options')
    world:release()
end

return Module
