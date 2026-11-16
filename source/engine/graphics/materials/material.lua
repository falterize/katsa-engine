local readValue = require('../../math.managedValue').read
local pairs = require('../../math.array').pairs
local ipairs = require('../../math.array').ipairs
local Programs = require('../shaders.programs')
local Samplers = require('../shaders.samplers')

-- A material is a template program with user shaders spliced in (see graphics/shaders/composer).
--   kind = 'world': options.template (default the spatial world program) plus options.shaders,
--                   a list of parsed shaders; builds the main program and its shadow program.
--   kind = 'ui':    options.code or options.path, a complete shader in the katsa dialect.
local Material = {}
Material.__index = Material

local worldTemplate = 'assets/shaders/engine/world.glsl'
local shadowTemplate = 'assets/shaders/engine/shadow.glsl'

local function vertexModified(shaders)
    for _, shader in ipairs(shaders) do
        if shader.entries.vertex then
            return true
        end
    end
    return false
end

local function newWorld(resources, options)
    local shaders = options.shaders or {}
    local shader, program = Programs.compile(options.template or worldTemplate, {
        shaders = shaders,
        defines = options.defines,
    })
    resources:own(shader)
    local shadowShader
    if not program.modes.shadows_disabled then
        shadowShader = resources:own((Programs.compile(shadowTemplate, {
            shaders = shaders,
            entries = { vertex = true },
        })))
    end
    return shader, program, shadowShader
end

function Material.new(resources, options)
    options = options or {}
    local kind = options.kind or 'world'
    assert(kind == 'world' or kind == 'ui', 'Material.kind must be world or ui')
    local shader, program, shadowShader
    if kind == 'world' then
        shader, program, shadowShader = newWorld(resources, options)
    else
        local code = options.code or (options.path and assert(katsa.filesystem.read(options.path)))
        assert(code, 'UI material requires code or path')
        local success
        success, shader = pcall(katsa.graphics.newShader, code)
        assert(success, 'Material shader failed: ' .. tostring(shader))
        resources:own(shader)
    end
    local uniforms = options.uniforms or {}
    if program then
        for name, value in pairs(program.defaults) do
            if uniforms[name] == nil then
                uniforms[name] = value
            end
        end
    end
    local modifiesVertex = program ~= nil and vertexModified(options.shaders or {})
    local modes = program and program.modes or {}
    local self = setmetatable({
        vertexModified = modifiesVertex,
        vertexAnimated = options.animated == true and modifiesVertex,
        kind = kind,
        resources = resources,
        shader = shader,
        shadowShader = shadowShader,
        program = program,
        uniforms = uniforms,
        animated = options.animated == true,
        modes = modes,
        -- Draw state requested through render_mode (nil = the object's own setting).
        blend = modes.blend_add and 'add' or modes.blend_mul and 'multiply' or nil,
        cull = modes.cull_back and 'back' or modes.cull_front and 'front'
            or modes.cull_disabled and 'none' or nil,
        depthWrite = not modes.depth_draw_never,
        castsShadow = not modes.shadows_disabled,
    }, Material)
    -- Samplers the renderer feeds: `uniform sampler2D t : hint_screen_texture;` is the opaque
    -- scene colour, `hint_depth_texture` its depth. Such a material draws in the transparent pass.
    for compiled, meta in pairs(program and program.uniforms or {}) do
        local hints = meta.info.hints
        if hints.hint_screen_texture then
            self.screenUniform = compiled
        elseif hints.hint_depth_texture then
            self.depthUniform = compiled
        end
    end
    self.needsScene = self.screenUniform ~= nil or self.depthUniform ~= nil
    return self
end

-- Sends every material uniform the compiler kept. Uniforms a driver optimised away (declared
-- but never read by the stage) are skipped instead of reported. Sampler uniforms hold a path, a
-- node that offers a texture or a texture (see shaders/samplers.lua).
local function send(self, shader)
    local meta = self.program and self.program.uniforms
    for name, value in pairs(self.uniforms) do
        if shader:hasUniform(name) then
            local info = meta and meta[name] and meta[name].info
            if info and info.sampler then
                if not (info.hints.hint_screen_texture or info.hints.hint_depth_texture) then
                    local texture = Samplers.resolve(self.resources, value, info)
                    if texture then
                        shader:send(name, texture)
                    end
                end
            else
                shader:send(name, readValue(value))
            end
        end
    end
end

function Material:bindShadow()
    if self.shadowShader then
        send(self, self.shadowShader)
    end
end

function Material:set(name, value)
    assert(
        self.uniforms[name] ~= nil or self.shader:hasUniform(name),
        'Unknown or unused material uniform: ' .. name
    )
    self.uniforms[name] = value
    return self
end

-- `time` is only for UI materials, which are not drawn by the world renderer that sends the
-- shared frame uniforms.
function Material:bind(time)
    if time and self.shader:hasUniform('time') then
        self.shader:send('time', time)
    end
    send(self, self.shader)
end

return Material
