-- Shader composer: parsing, built-in tables, namespacing, #specialize, flags and error mapping.
local Composer = require('source.engine.graphics.shaders.composer')

local Module = {}

local snap = [[
shader_type spatial;
render_mode unshaded;

uniform float snapScale : hint_range(1.0, 200.0) = 75.0;
uniform vec4 tint : source_color = vec4(1.0, 0.5, 0.25, 1.0);
varying vec2 affineUv;

float snapValue(float v) {
    return floor(snapScale * v) / snapScale;
}

void vertex() {
    vec4 p = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    POSITION = PROJECTION_MATRIX * p;
    POSITION.x = snapValue(POSITION.x / POSITION.w) * POSITION.w;
    affineUv = UV * POSITION.w;
}

void fragment() {
    ALBEDO = tint.rgb;
}
]]

function Module.run(self)
    local files = {
        ['t.glsl'] = '#specialize bool skinEnabled\n#user_code\nvoid main() {}\n',
    }
    local options = {
        read = function(path)
            return files[path]
        end,
    }
    local shader = Composer.parseText(snap, 'snap.glsl')
    self:check(
        shader.type == 'spatial' and shader.modes.unshaded,
        'The composer parses shader_type and render_mode'
    )
    local uniform = shader.uniforms[1]
    self:check(
        uniform.name == 'snapScale' and uniform.default == 75 and uniform.hints.hint_range,
        'Uniform hints and defaults are kept as metadata'
    )
    local program = Composer.build('t.glsl', {
        shaders = { shader },
        read = options.read,
        constants = { skinEnabled = true },
    })
    local text = program.source
    self:check(
        text:find('const bool skinEnabled = true;', 1, true) and not text:find(': hint_range', 1, true),
        'specialize becomes a constant and hints never reach GLSL'
    )
    self:check(
        text:find('s1_snapValue', 1, true)
            and text:find('uniform float s1_snapScale;', 1, true)
            and program.defaults.s1_snapScale == 75,
        'User identifiers are namespaced and defaults are reported'
    )
    self:check(
        program.flags.KATSA_USER_POSITION and program.flags.KATSA_USER_UNSHADED,
        'POSITION and unshaded set template flags'
    )
    local plain = Composer.build('t.glsl', { read = options.read })
    self:check(
        plain.source:find('uniform bool skinEnabled;', 1, true) ~= nil,
        'Without constants specialize stays a uniform'
    )
    local ok, message = pcall(Composer.parseText, 'shader_type spatial;\nvoid light() {\n', 'bad.glsl')
    self:check(not ok and tostring(message):find('bad.glsl', 1, true), 'Parse errors name the file')
    ok, message = pcall(
        Composer.parseText,
        'shader_type canvas_item;\nvoid light() {}\n',
        'bad2.glsl'
    )
    self:check(not ok and tostring(message):find('light', 1, true), 'Unknown entry points are rejected')
end

return Module
