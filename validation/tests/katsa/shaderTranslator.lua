local Translator = require('source.katsa.graphics.shaderTranslator')

return function(T)
    local source = [[
#pragma language glsl3
varying vec2 uv;
attribute highp vec4 skinJoints;
attribute vec3 vertexNormal;
extern number amount;
#ifdef VERTEX
vec4 position(mat4 transformProjection, vec4 vertexPosition) {
    uv = VertexTexCoord.xy;
    return transformProjection * vertexPosition;
}
#endif
#ifdef PIXEL
vec4 effect(vec4 color, Image tex, vec2 texCoord, vec2 screenCoord) {
    return Texel(tex, texCoord) * color * amount;
}
#endif
]]
    for _, target in ipairs({ 'desktop', 'es' }) do
        local result = assert(Translator.translate(source, { target = target }))
        local version = target == 'es' and '#version 300 es' or '#version 330 core'
        T.check(result.vertex:sub(1, #version) == version, target .. ' vertex version header')
        T.check(result.pixel:sub(1, #version) == version, target .. ' pixel version header')
        T.check(result.vertex:find('#define VERTEX 1', 1, true), target .. ' vertex stage define')
        T.check(result.pixel:find('#define PIXEL 1', 1, true), target .. ' pixel stage define')
        T.check(result.vertex:find('#define varying out', 1, true), target .. ' vertex varying')
        T.check(result.pixel:find('#define varying in', 1, true), target .. ' pixel varying')
        T.check(
            result.vertex:find('layout(location = 3) in highp vec4 skinJoints;', 1, true),
            target .. ' first custom attribute at location 3'
        )
        T.check(
            result.vertex:find('layout(location = 4) in vec3 vertexNormal;', 1, true),
            target .. ' second custom attribute at location 4'
        )
        T.check(result.attributes.skinJoints.location == 3, target .. ' attribute table')
        T.check(
            result.attributeOrder[1] == 'skinJoints' and result.attributeOrder[2] == 'vertexNormal',
            target .. ' attribute order'
        )
        T.check(
            result.pixel:find('attribute highp vec4 skinJoints', 1, true),
            target .. ' pixel keeps the guarded source untouched'
        )
        T.check(
            result.pixel:find('void main()', 1,
                true) and result.vertex:find('void main()', 1, true),
            target .. ' both stages get a main'
        )
    end
    local es = assert(Translator.translate(source, { target = 'es' }))
    T.check(es.pixel:find('precision highp float;', 1, true), 'ES declares float precision')
    T.check(es.pixel:find('precision highp sampler2D;', 1, true), 'ES declares sampler precision')
    local desktop = assert(Translator.translate(source))
    T.check(not desktop.pixel:find('precision highp float', 1, true), 'desktop has no precision')

    -- Stage presence follows LÖVE: only the stage whose entry point exists receives the code.
    local pixelOnly =
        assert(Translator.translate('vec4 effect(vec4 c, Image t, vec2 uv, vec2 p) { discard; }'))
    T.check(
        pixelOnly.vertex:find('transformProjection * vertexPosition', 1, true),
        'default position'
    )
    T.check(
        not pixelOnly.vertex:find('discard', 1, true),
        'pixel-only code stays out of the vertex stage'
    )
    local vertexOnly =
        assert(Translator.translate('vec4 position(mat4 m, vec4 v) { return m * v; }'))
    T.check(vertexOnly.pixel:find('Texel(tex, textureCoords) * color', 1, true), 'default effect')

    -- glsl1 compatibility names.
    local legacy = assert(
        Translator.translate(
            'vec4 effect(vec4 c, Image t, vec2 uv, vec2 p) { return texture2D(t, uv); }'
        )
    )
    T.check(
        legacy.dialect == 'glsl1' and legacy.pixel:find('#define texture2D texture', 1, true),
        'glsl1 texture2D'
    )

    -- Errors.
    T.check(select(2, Translator.translate('')) ~= nil, 'empty source rejected')
    T.check(
        select(2, Translator.translate('float x;')) ~= nil,
        'source without entry points rejected'
    )
    T.check(
        select(2, Translator.translate(source, { target = 'metal' })) ~= nil,
        'unknown target rejected'
    )
    T.check(
        select(
            2,
            Translator.translate(
                '#pragma language glsl9\nvec4 effect(vec4 c, Image t, vec2 u, vec2 p){return c;}'
            )
        ) ~= nil,
        'unknown language rejected'
    )
    T.check(
        select(
            2,
            Translator.translate(
                'attribute vec4 VertexPosition;\nvec4 position(mat4 m, vec4 v){return m*v;}'
            )
        ) ~= nil,
        'redeclared built-in attribute rejected'
    )
    local commented = assert(
        Translator.translate(
            '// vec4 position(mat4 m, vec4 v)\nvec4 effect(vec4 c, Image t, vec2 u, vec2 '
                .. 'p){return c;}'
        )
    )
    T.check(
        commented.attributeOrder[1] == nil and commented.vertex:find('default') == nil,
        'comments ignored'
    )
    local mrt = assert(
        Translator.translate(
            'vec4 effect(vec4 c, Image t, vec2 u, vec2 p){ katsa_Canvases[1] = c; return c; }'
        )
    )
    T.check(mrt.pixel:find('out vec4 katsa_Canvases[4]', 1, true) ~= nil, 'multiple render targets')
end
