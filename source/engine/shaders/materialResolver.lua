local ipairs = require('../math.array').ipairs
local pairs = require('../math.array').pairs
local Material = require('../graphics.material')

local Resolver = {}
local sections = {
    vertexDeclarations = true,
    vertexCode = true,
    fragmentDeclarations = true,
    fragmentCode = true,
}

local function read(path)
    local source = assert(katsa.filesystem.read(path), 'Missing Shader3D source: ' .. path)
    local result = {}
    local current
    for line in (source .. '\n'):gmatch('(.-)\n') do
        local marker = line:match('^%s*//%s*@(%w+)%s*$')
        if marker then
            assert(sections[marker], 'Unknown Shader3D section: ' .. marker)
            current = marker
            result[current] = ''
        elseif current then
            result[current] = result[current] .. line .. '\n'
        end
    end
    assert(
        result.vertexCode or result.fragmentCode,
        'Shader3D needs //@vertexCode or //@fragmentCode sections'
    )
    return result
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
    require('source.engine.shaders.systemLayers').resolve(world, object, active)
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
            uniforms = {},
            template = particle and 'assets/shaders/particles/sprite.glsl' or nil,
        }
        local mappings = {}
        for index, node in ipairs(active) do
            local code = read(world.resources:canonical(node.shaderPath))
            local names = {}
            for name, value in pairs(node.uniforms) do
                local compiled = 'effect' .. index .. '_' .. name
                names[name] = compiled
                options.uniforms[compiled] = value
                mappings[compiled] = { node = node, key = name }
            end
            for section in pairs(sections) do
                local chunk = code[section] or ''
                for name, compiled in pairs(names) do
                    chunk = chunk:gsub('%f[%w_]' .. name .. '%f[^%w_]', compiled)
                end
                if section:match('Code$') and chunk ~= '' then
                    chunk = '{\n' .. chunk .. '\n}\n'
                end
                options[section] = (options[section] or '') .. chunk
            end
            options.animated = options.animated or node.animated
        end
        material = Material.new(world.resources, options)
        material.uniformMappings = mappings
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
    for name, mapping in pairs(material.uniformMappings) do
        material.uniforms[name] = mapping.node.uniforms[mapping.key]
    end
    object._shaderBoundsPadding = padding
    object._shaderBoundsUnknown = unknown
    object._resolvedMaterial = material
    return material
end

return Resolver
