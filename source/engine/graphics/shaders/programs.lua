-- Compiles engine and user shaders through the composer.
--
-- Programs.compile('assets/shaders/engine/world.glsl', {
--     shaders = { userShader },          -- parsed with Programs.parse
--     defines = { KATSA_SOLID = true },
--     constants = { skinEnabled = false },
-- })
-- returns the native shader and the composed program (uniform metadata, modes, flags).
-- Compile errors are reported against the authored files, not the composed text.
local Composer = require('./composer')

local Programs = {}

-- Reads and parses one user shader file. `kind` limits the accepted shader_type.
function Programs.parse(path, kind)
    return Composer.user(path, { kind = kind })
end

-- Parses shader source held in memory (tests, generated shaders).
function Programs.parseText(text, label, kind)
    return Composer.parseText(text, label, { kind = kind })
end

function Programs.compile(template, options)
    local program = Composer.build(template, options)
    local ok, shader = pcall(katsa.graphics.newShader, program.source)
    if not ok then
        error(template .. ': ' .. Composer.explain(program, shader), 0)
    end
    return shader, program
end

return Programs
