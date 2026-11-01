local readValue = require('source.engine.math.managedValue').read
local pairs = require('source.engine.math.array').pairs

local Material = {}
Material.__index = Material

local function insert(source, marker, code)
    local start, finish = source:find(marker, 1, true)
    assert(start, 'Missing material hook: ' .. marker)
    return source:sub(1, start - 1) .. (code or '') .. source:sub(finish + 1)
end

function Material.new(resources, options)
    options = options or {}
    local kind = options.kind or 'world'
    assert(kind == 'world' or kind == 'ui', 'Material.kind must be world or ui')
    local code
    if kind == 'world' then
        code = require('source.engine.graphics.shaderSource').read(
            options.template or 'assets/shaders/engine/world.glsl'
        )
        code = code:gsub('// EARLY_DEPTH_BEGIN.-// EARLY_DEPTH_END', '')
        code = insert(code, '// MATERIAL_VERTEX_DECLARATIONS', options.vertexDeclarations)
        code = insert(code, '// MATERIAL_PIXEL_DECLARATIONS', options.fragmentDeclarations)
        code = insert(code, '// MATERIAL_VERTEX', options.vertexCode)
        code = insert(code, '// MATERIAL_PIXEL', options.fragmentCode)
    else
        code = options.code or (options.path and assert(love.filesystem.read(options.path)))
        assert(code, 'UI material requires code or path')
    end
    local success, shader = pcall(love.graphics.newShader, code)
    assert(success, 'Material shader failed: ' .. tostring(shader))
    resources:own(shader)
    local self = setmetatable({
        vertexModified = options.vertexCode ~= nil and options.vertexCode ~= '',
        vertexAnimated = options.animated == true
            and options.vertexCode ~= nil
            and options.vertexCode ~= '',
        kind = kind,
        shader = shader,
        uniforms = options.uniforms or {},
        animated = options.animated == true,
        code = code,
    }, Material)
    for name in pairs(self.uniforms) do
        assert(shader:hasUniform(name), 'Unknown or unused material uniform: ' .. name)
    end
    if kind == 'world' then
        local shadowCode = assert(love.filesystem.read('assets/shaders/engine/shadow.glsl'))
        shadowCode =
            insert(shadowCode, '// MATERIAL_VERTEX_DECLARATIONS', options.vertexDeclarations)
        shadowCode = insert(shadowCode, '// MATERIAL_VERTEX', options.vertexCode)
        local ok, shadowShader = pcall(love.graphics.newShader, shadowCode)
        assert(ok, 'Material shadow shader failed: ' .. tostring(shadowShader))
        self.shadowShader = resources:own(shadowShader)
    end
    return self
end

function Material:bindShadow(time)
    local shader = self.shadowShader
    if shader:hasUniform('materialTime') then
        shader:send('materialTime', time or 0)
    end
    for name, value in pairs(self.uniforms) do
        if shader:hasUniform(name) then
            shader:send(name, readValue(value))
        end
    end
end

function Material:set(name, value)
    assert(self.shader:hasUniform(name), 'Unknown or unused material uniform: ' .. name)
    self.uniforms[name] = value
    return self
end

function Material:bind(time)
    if self.shader:hasUniform('materialTime') then
        self.shader:send('materialTime', time or 0)
    end
    for name, value in pairs(self.uniforms) do
        self.shader:send(name, readValue(value))
    end
end

return Material
