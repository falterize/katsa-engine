local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
local readValue = require('../../math.managedValue').read
local Programs = require('./programs')
local Composer = require('./composer')
local Samplers = require('./samplers')

-- Shader3D nodes whose file says `shader_type sky` or `shader_type fog` do not style meshes: they
-- replace the world background and reshape the volumetric fog (the Godot 4 shader types of the
-- same names). This module finds them and compiles them into their engine templates.
local EnvironmentShaders = {
    templates = {
        sky = 'assets/shaders/engine/skyShader.glsl',
        fog = 'assets/shaders/engine/post/volumetricFog.glsl',
    },
}

-- The shader_type of a Shader3D node's file: 'spatial' unless it is sky or fog. A file that does
-- not parse counts as spatial so the mesh pipeline reports the error against the user's file.
function EnvironmentShaders.kind(world, node)
    if node._environmentKindPath == node.shaderPath then
        return node._environmentKind
    end
    local cache = world._environmentParsed
    if not cache then
        cache = {}
        world._environmentParsed = cache
    end
    local path = world.resources:canonical(node.shaderPath)
    local info = cache[path]
    if not info then
        local ok, parsed = pcall(Composer.user, path)
        info = { type = ok and parsed.type or 'spatial', parsed = ok and parsed or nil }
        cache[path] = info
    end
    node._environmentKindPath, node._environmentKind = node.shaderPath, info.type
    node._environmentParsed = info.parsed
    return info.type
end

-- The first enabled Shader3D of the given type ('sky' or 'fog'), or nil.
function EnvironmentShaders.find(world, kind)
    for _, node in ipairs(world.shaderNodes or {}) do
        if node.enabled ~= false and node.shaderPath ~= '' and EnvironmentShaders.kind(world, node) == kind then
            return node
        end
    end
end

-- Compiles (once per file) the template of `kind` with the node's shader. Returns the shader and
-- the program whose uniform table maps compiled names to the node's own uniforms.
function EnvironmentShaders.program(world, node, kind)
    local cache = world._environmentPrograms
    if not cache then
        cache = {}
        world._environmentPrograms = cache
    end
    local key = kind .. ':' .. world.resources:canonical(node.shaderPath)
    local entry = cache[key]
    if not entry then
        local shader, program = Programs.compile(EnvironmentShaders.templates[kind], {
            kind = kind,
            shaders = { node._environmentParsed },
            entries = { fragment = true },
        })
        world.resources:own(shader)
        entry = { shader = shader, program = program }
        cache[key] = entry
    end
    return entry.shader, entry.program
end

-- Sends the node's uniform values (or the file's defaults) to the compiled shader.
function EnvironmentShaders.send(shader, program, node)
    for compiled, meta in pairs(program.uniforms) do
        local value = node.uniforms[meta.name]
        if value == nil then
            value = program.defaults[compiled]
        end
        if value ~= nil and shader:hasUniform(compiled) then
            if meta.info.sampler then
                value = Samplers.resolve((node._world or node._sceneWorld).resources, value, meta.info)
                if value then
                    shader:send(compiled, value)
                end
            else
                shader:send(compiled, readValue(value))
            end
        end
    end
end

return EnvironmentShaders
