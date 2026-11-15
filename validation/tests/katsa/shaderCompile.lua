-- Compiles every shader of the project on a real GL driver, for desktop and GLES targets.
--
-- Engine shaders go through the composer exactly like the renderer does (includes, #specialize,
-- flags). Every user shader found in scene and runtime folders is composed with each template
-- of its shader_type, so a template change that breaks a scene shader fails here.
local Translator = require('source.katsa.graphics.shaderTranslator')
local Composer = require('source.engine.graphics.shaders.composer')

-- The standalone runner has no katsa.filesystem: read straight from disk.
local function read(path)
    local file = io.open(path, 'rb')
    if not file then
        return nil
    end
    local text = file:read('*a')
    file:close()
    return text
end

local function find(directory, excluded)
    local files = {}
    local pipe = io.popen('find ' .. directory .. ' -name "*.glsl" | sort')
    for line in pipe:lines() do
        if not (excluded and line:find(excluded, 1, true)) then
            files[#files + 1] = line
        end
    end
    pipe:close()
    return files
end

-- Variants that exercise the template branches the renderer selects.
local worldVariants = {
    { name = 'general' },
    {
        name = 'rigid solid',
        defines = { KATSA_SOLID = true, KATSA_EARLY_DEPTH = true, KATSA_NO_DIRECTIONAL = true },
        constants = { skinEnabled = false, lightCount = 3, unlit = false, receiveShadow = false },
    },
    {
        name = 'skinned masked standard shadows',
        defines = {
            KATSA_LIGHT_MASK = true,
            KATSA_SHADOW_STANDARD = true,
            KATSA_SHADOW_SAMPLES = 4,
        },
        constants = { skinExtended = true, lightCount = 8, surfaceEnabled = true },
    },
}

local function templates(kind, shaders)
    if kind == 'sky' then
        return { { 'assets/shaders/engine/skyShader.glsl', { entries = { fragment = true } } } }
    end
    if kind == 'fog' then
        return {
            {
                'assets/shaders/engine/post/volumetricFog.glsl',
                { entries = { fragment = true } },
            },
        }
    end
    if kind == 'canvas_item' then
        return { { 'assets/shaders/engine/canvas/item.glsl', {} } }
    end
    local list = {}
    for _, variant in ipairs(worldVariants) do
        list[#list + 1] = {
            'assets/shaders/engine/world.glsl',
            { defines = variant.defines, constants = variant.constants },
            ' (' .. variant.name .. ')',
        }
    end
    list[#list + 1] = { 'assets/shaders/engine/shadow.glsl', { entries = { vertex = true } } }
    list[#list + 1] = { 'assets/shaders/engine/particles/sprite.glsl', { entries = { vertex = true, fragment = true } } }
    return list
end

local function check(T, checker, target, label, template, options)
    options.read = read
    local ok, program = pcall(Composer.build, template, options)
    T.check(ok, target .. ' composes ' .. label .. ': ' .. tostring(program))
    if not ok then
        return
    end
    local translated, message = Translator.translate(program.source, { target = target })
    T.check(translated ~= nil, target .. ' translates ' .. label .. ' ' .. tostring(message))
    if translated then
        local linked, log = checker:link(translated)
        T.check(linked, target .. ' compiles and links ' .. label .. ': ' .. Composer.explain(program, log))
    end
end

return function(T)
    local Headless = require('source.katsa.platform.headlessEgl')
    local Check = require('source.katsa.graphics.glShaderCheck')
    local engine = {}
    for _, path in ipairs(find('assets/shaders', '/chunks/')) do
        engine[#engine + 1] = path
    end
    T.check(#engine >= 5, 'project shader files found')
    local users = {}
    for _, directory in ipairs({ 'game/scenes', 'game/runtime', 'validation/tests/fixtures/shaders' }) do
        for _, path in ipairs(find(directory)) do
            -- Include-only files have no shader_type; they are compiled through their users.
            if (read(path) or ''):find('shader_type', 1, true) then
                users[#users + 1] = path
            end
        end
    end
    T.check(#users >= 8, 'user shader files found')
    for _, target in ipairs({ 'desktop', 'es' }) do
        local platform, reason = Headless.new(target)
        if not platform then
            T.skip('headless ' .. target .. ': ' .. tostring(reason))
        else
            local checker = assert(Check.new(platform))
            local renderer, vendor = checker:info()
            T.check(renderer ~= '' and vendor ~= '', target .. ' context reports ' .. renderer)
            for _, path in ipairs(engine) do
                if path:find('/world.glsl', 1, true) then
                    for _, variant in ipairs(worldVariants) do
                        check(T, checker, target, path .. ' (' .. variant.name .. ')', path, {
                            defines = variant.defines,
                            constants = variant.constants,
                        })
                    end
                else
                    check(T, checker, target, path, path, {})
                end
            end
            for _, path in ipairs(users) do
                local parsed = Composer.user(path, { read = read })
                for _, entry in ipairs(templates(parsed.type)) do
                    local options = entry[2]
                    options.shaders = { parsed }
                    check(T, checker, target, path .. ' in ' .. entry[1] .. (entry[3] or ''), entry[1], options)
                end
            end
            -- Attribute locations the translator promises must be what the driver reports.
            local translated = assert(Translator.translate(
                [[
attribute vec4 custom;
vec4 position(mat4 m, vec4 v) { return m * v + custom; }
]],
                { target = target }
            ))
            local ok, log = checker:link(translated)
            T.check(ok, target .. ' custom attribute location: ' .. tostring(log))
            -- A broken shader must fail with a driver message, not crash.
            local broken = assert(
                Translator.translate(
                    'vec4 effect(vec4 c, Image t, vec2 u, vec2 p){ return nope; }',
                    { target = target }
                )
            )
            local brokenOk, brokenLog = checker:link(broken)
            T.check(not brokenOk and #brokenLog > 0, target .. ' reports compile errors')
            platform:close()
        end
    end
end
