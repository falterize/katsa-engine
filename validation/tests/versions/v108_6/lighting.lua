-- lightInfluence replaces the boolean unlit everywhere through one component.
local Lighting = require('source.engine.components.illumination.lighting')
local Schema = require('source.engine.editor.inspectors.schema')
local World = require('source.engine.world.world')

local Module = {}

function Module.run(self)
    local legacy = { unlit = true }
    Lighting.normalize(legacy, 1)
    self:check(legacy.lightInfluence == 0 and legacy.unlit == nil, 'a legacy unlit = true becomes lightInfluence 0')
    legacy = { unlit = false }
    Lighting.normalize(legacy, 0)
    self:check(legacy.lightInfluence == 1, 'a legacy unlit = false becomes lightInfluence 1')
    local explicit = { unlit = true, lightInfluence = 0.5 }
    Lighting.normalize(explicit, 1)
    self:check(explicit.lightInfluence == 0.5, 'an explicit lightInfluence wins over the legacy flag')
    self:check(Lighting.influence({ canvas = {}, lightInfluence = 1 }) == 0, 'billboard canvases are never lit')
    self:check(Lighting.influence({ lightInfluence = 1, _systemEffects = { lighting = false } }) == 0, 'a system layer without lighting forces unlit')
    self:check(Lighting.influence({}) == 1, 'a node without the field is fully lit')

    local resources = self.manager.resources:scope()
    local world = World.new(resources)
    local mesh = world:create('Mesh3D', { name = 'LitMesh', size = { 1, 1, 1 } })
    local flat = world:create('Mesh3D', { name = 'FlatMesh', size = { 1, 1, 1 }, unlit = true })
    local decal = world:create('Decal3D', {}, mesh)
    local emitter = world:create('ParticleEmitter3D', {})
    local beam = world:create('Beam3D', {})
    self:check(mesh.lightInfluence == 1, 'meshes are lit by default')
    self:check(flat.lightInfluence == 0 and flat.unlit == nil, 'an authored unlit mesh is stored as lightInfluence 0')
    self:check(decal.lightInfluence == 0 and emitter.lightInfluence == 0 and beam.lightInfluence == 0, 'decals, particles and ribbons are unlit by default')
    local hint = Schema.descriptor(mesh, 'lightInfluence').hint
    self:check(hint ~= nil and hint == Schema.descriptor(emitter, 'lightInfluence').hint and hint == Schema.descriptor(beam, 'lightInfluence').hint, 'every class shares one lightInfluence description')
    self:check(Schema.descriptor(decal, 'lightInfluence').max == 1, 'lightInfluence is limited to 0..1')

    local light = world:create('PointLight3D', { name = 'Lamp' })
    self:check(mesh.castShadow == true and mesh.receiveShadow == true, 'meshes store explicit shadow defaults')
    self:check(light.castShadow == true, 'lights store an explicit castShadow default')
    local cast = Schema.descriptor(mesh, 'castShadow').hint
    self:check(cast ~= nil and cast == Schema.descriptor(light, 'castShadow').hint and cast == Schema.descriptor(emitter, 'castShadow').hint, 'meshes, lights and particles share the castShadow description')
    self:check(Schema.descriptor(mesh, 'shadowAlphaCutoff').hint == nil, 'meshes do not list the procedural shadowAlphaCutoff')
    world:release()
end

return Module
