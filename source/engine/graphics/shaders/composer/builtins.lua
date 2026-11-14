-- The contract between user shaders and engine templates.
--
-- Every entry point of a shader type is a function whose parameters are the built-in variables
-- of that stage (`in` = read only, `inout` = read and write, `out` = write only). The composer
-- turns `void vertex() { ... }` into a real GLSL function with exactly these parameters, and
-- the engine template declares locals with the same names before it calls the function.
--
-- Documented in docs/guides/rendering/shaders.md; keep that guide in step with this file.
local Builtins = {}

local function p(qualifier, type, name)
    return { qualifier = qualifier, type = type, name = name }
end

Builtins.types = {
    spatial = {
        vertex = {
            p('inout', 'highp vec3', 'VERTEX'),
            p('inout', 'highp vec3', 'NORMAL'),
            p('inout', 'vec2', 'UV'),
            p('inout', 'vec4', 'COLOR'),
            p('in', 'highp mat4', 'MODEL_MATRIX'),
            p('in', 'highp mat4', 'VIEW_MATRIX'),
            p('in', 'highp mat4', 'PROJECTION_MATRIX'),
            p('in', 'highp mat4', 'MODELVIEW_MATRIX'),
            p('in', 'highp float', 'TIME'),
            p('in', 'highp vec2', 'VIEWPORT_SIZE'),
            p('in', 'highp vec3', 'CAMERA_POSITION'),
            p('out', 'highp vec4', 'POSITION'),
        },
        fragment = {
            p('in', 'highp vec4', 'FRAGCOORD'),
            p('in', 'vec2', 'UV'),
            p('in', 'vec4', 'COLOR'),
            p('in', 'highp vec3', 'WORLD_POSITION'),
            p('in', 'highp vec3', 'VIEW'),
            p('in', 'bool', 'FRONT_FACING'),
            p('in', 'highp float', 'TIME'),
            p('in', 'vec4', 'MODULATE'),
            p('in', 'highp sampler2D', 'TEXTURE'),
            p('inout', 'vec3', 'ALBEDO'),
            p('inout', 'float', 'ALPHA'),
            p('inout', 'highp vec3', 'NORMAL'),
            p('inout', 'float', 'ROUGHNESS'),
            p('inout', 'float', 'METALLIC'),
            p('inout', 'vec3', 'EMISSION'),
            p('inout', 'float', 'AO'),
        },
        light = {
            p('in', 'highp vec3', 'NORMAL'),
            p('in', 'highp vec3', 'VIEW'),
            p('in', 'highp vec3', 'LIGHT'),
            p('in', 'vec3', 'LIGHT_COLOR'),
            p('in', 'float', 'ATTENUATION'),
            p('in', 'vec3', 'ALBEDO'),
            p('in', 'float', 'ROUGHNESS'),
            p('in', 'float', 'METALLIC'),
            p('in', 'highp float', 'TIME'),
            p('inout', 'vec3', 'DIFFUSE_LIGHT'),
            p('inout', 'vec3', 'SPECULAR_LIGHT'),
        },
    },
    canvas_item = {
        vertex = {
            p('inout', 'highp vec2', 'VERTEX'),
            p('inout', 'vec2', 'UV'),
            p('inout', 'vec4', 'COLOR'),
            p('in', 'highp vec2', 'CANVAS_VERTEX'),
            p('in', 'highp float', 'TIME'),
        },
        fragment = {
            p('in', 'highp vec4', 'FRAGCOORD'),
            p('in', 'highp vec2', 'UV'),
            p('in', 'highp vec2', 'SCREEN_PIXEL'),
            p('in', 'vec4', 'VERTEX_COLOR'),
            p('in', 'highp float', 'TIME'),
            p('in', 'highp sampler2D', 'TEXTURE'),
            p('in', 'highp vec2', 'CANVAS_SIZE'),
            p('in', 'highp vec2', 'REGION_ORIGIN'),
            p('in', 'highp vec2', 'REGION_SIZE'),
            p('in', 'highp vec2', 'REGION_UV'),
            p('inout', 'vec4', 'COLOR'),
        },
    },
}

-- Render modes a shader type accepts (validated by the parser).
Builtins.modes = {
    spatial = {
        unshaded = true,
        cull_disabled = true,
        cull_front = true,
        cull_back = true,
        blend_mix = true,
        blend_add = true,
        blend_mul = true,
        depth_draw_never = true,
        shadows_disabled = true,
    },
    canvas_item = {
        blend_mix = true,
        blend_add = true,
        blend_mul = true,
    },
}

return Builtins
