local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
local Material = require('../materials.material')
local Programs = require('./programs')

local Resolver = {}

-- Parsed user shaders are cached per world: a scene restart (hot reload included) starts empty.
local function shaderFor(world, node)
    local path = world.resources:canonical(node.shaderPath)
    local cache = world._parsedShaders
    if not cache then
        cache = {}
        world._parsedShaders = cache
    end
    local info = cache[path]
    if not info then
        info = Programs.parse(path, 'spatial')
        cache[path] = info
    end
    return info
end

function Resolver.resolve(world, object)
    local available = world._renderResolving and world._renderShaderNodes or world.shaderNodes
    if not available or #available == 0 then
        if rawget(object, '_resolvedMaterial') then
            rawset(object, '_resolvedMaterial', nil)
        end
        object._shaderBoundsPadding = 0
        object._shaderBoundsUnknown = false
        if rawget(object, '_systemEffects') then
            rawset(object, '_systemEffects', nil)
        end
        return nil
    end
    local nodes = object._shaderCandidates or {}
    object._shaderCandidates = nodes
    for i = #nodes, 1, -1 do
        nodes[i] = nil
    end
    for _, shader in ipairs(available or {}) do
        if shader.enabled ~= false and shader.shaderPath ~= '' then
            local ancestor = object
            while ancestor do
                if
                    ancestor:isA('World2D')
                    or ancestor:isA('UINode')
                    or ancestor:isA('BillboardUI')
                then
                    break
                end
                if ancestor == shader.parent then
                    nodes[#nodes + 1] = shader
                    break
                end
                if ancestor:isA('World3D') then
                    break
                end
                ancestor = ancestor.parent
            end
        end
    end
    local active = world.shaderLayers:resolve(nodes, object._activeShaders)
    object._activeShaders = active
    require('source.engine.graphics.shaders.systemLayers').resolve(world, object, active)
    if #active == 0 then
        object._resolvedMaterial = nil
        object._shaderBoundsPadding = 0
        object._shaderBoundsUnknown = false
        return nil
    end
    local keys = object._shaderKeys or {}
    object._shaderKeys = keys
    local changed = #keys ~= #active
    for i, node in ipairs(active) do
        if node._pathForKey ~= node.shaderPath then
            node._pathForKey = node.shaderPath
            node._materialPathKey = tostring(node) .. ':' .. node.shaderPath
        end
        if keys[i] ~= node._materialPathKey then
            changed = true
            keys[i] = node._materialPathKey
        end
    end
    for i = #keys, #active + 1, -1 do
        keys[i] = nil
    end
    local particle = object:isA('ParticleEmitter3D')
        or object:isA('Beam3D')
        or object:isA('Trail3D')
    if changed or not object._shaderStackSignature then
        object._shaderStackSignature = (particle and 'particle:' or 'world:')
            .. table.concat(keys, '|')
    end
    local key = object._shaderStackSignature
    world._shaderMaterials = world._shaderMaterials or {}
    local material = world._shaderMaterials[key]
    if not material then
        local options = {
            kind = 'world',
            shaders = {},
            template = particle and 'assets/shaders/engine/particles/sprite.glsl' or nil,
        }
        for index, node in ipairs(active) do
            options.shaders[index] = shaderFor(world, node)
            options.animated = options.animated or node.animated
        end
        material = Material.new(world.resources, options)
        -- Compiled uniform name -> the Shader3D node and key that feed it.
        local mappings = {}
        for compiled, meta in pairs(material.program.uniforms) do
            mappings[compiled] = { node = active[meta.shader], key = meta.name }
        end
        material.uniformMappings = mappings
        for index, node in ipairs(active) do
            for name in pairs(node.uniforms) do
                assert(
                    material.program.uniforms['s' .. index .. '_' .. name],
                    ('Shader3D %s sets uniform "%s" that %s does not declare'):format(
                        tostring(node.name),
                        name,
                        node.shaderPath
                    )
                )
            end
        end
        world._shaderMaterials[key] = material
    end
    material.animated = false
    material.vertexAnimated = false
    local padding = 0
    local unknown = false
    for _, node in ipairs(active) do
        material.animated = material.animated or node.animated
        if material.vertexModified then
            material.vertexAnimated = material.vertexAnimated or node.animated
            if node.boundsMode ~= 'Padding' then
                unknown = true
            else
                padding = math.max(padding, node.shadowBoundsPadding)
            end
        end
    end
    local defaults = material.program.defaults
    for name, mapping in pairs(material.uniformMappings) do
        local value = mapping.node.uniforms[mapping.key]
        if value == nil then
            value = defaults[name]
        end
        material.uniforms[name] = value
    end
    object._shaderBoundsPadding = padding
    object._shaderBoundsUnknown = unknown
    object._resolvedMaterial = material
    return material
end

return Resolver
