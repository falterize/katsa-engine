-- Compiles every shader file of the project (and the translator fixtures) on a real GL driver.
-- The engine resolves `// @include` before newShader; the test does the same.
local Translator = require('source.katsa.graphics.shaderTranslator')

local function read(path)
    local file = assert(io.open(path, 'rb'), path)
    local text = file:read('*a')
    file:close()
    return text
end

local function resolve(text)
    return (
        text:gsub('//%s*@include%s+([^\n\r]+)', function(path)
            return read(path)
        end)
    )
end

-- Included libraries and material hook snippets have no entry point of their own.
local fragments = {
    ['assets/shaders/engine/meshTransform.glsl'] = true,
    ['assets/shaders/engine/shadowSampling.glsl'] = true,
    ['assets/shaders/examples/pixel3D.glsl'] = true,
    ['assets/shaders/examples/tint3D.glsl'] = true,
    ['assets/shaders/examples/wave3D.glsl'] = true,
}

local function list(directory)
    local files = {}
    local pipe = io.popen('find ' .. directory .. ' -name "*.glsl" | sort')
    for line in pipe:lines() do
        if not fragments[line] then
            files[#files + 1] = line
        end
    end
    pipe:close()
    return files
end

return function(T)
    local Headless = require('source.katsa.platform.headlessEgl')
    local Check = require('source.katsa.graphics.glShaderCheck')
    local files = list('assets/shaders')
    T.check(#files >= 5, 'project shader files found')
    for _, target in ipairs({ 'desktop', 'es' }) do
        local platform, reason = Headless.new(target)
        if not platform then
            T.skip('headless ' .. target .. ': ' .. tostring(reason))
        else
            local checker = assert(Check.new(platform))
            local renderer, vendor = checker:info()
            T.check(renderer ~= '' and vendor ~= '', target .. ' context reports ' .. renderer)
            for _, path in ipairs(files) do
                local translated, message =
                    Translator.translate(resolve(read(path)), { target = target })
                T.check(
                    translated ~= nil,
                    target .. ' translates ' .. path .. ' ' .. tostring(message)
                )
                if translated then
                    local ok, log = checker:link(translated)
                    T.check(ok, target .. ' compiles and links ' .. path .. ': ' .. tostring(log))
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
