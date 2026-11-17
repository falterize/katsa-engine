-- Inspector descriptions of meshes, decals, surface and billboard UI, cameras and shaders.
-- Editor text only: the classes carry no hint of their own.
-- Shape: { ClassName = { property = 'text' } }; a subclass inherits its base class entries.
local Common = require('./common')

return {
    Camera3D = {
        far = 'Far clip distance; must be above near.',
        fov = 'Vertical field of view in degrees. Linked to focalLength.',
        near = 'Perspective near clip distance; must be below far.',
        projectionMode = 'Perspective shrinks distant objects; Orthographic keeps a constant '
            .. 'scale.',
    },
    Decal3D = {
        brightness = Common.shared.surfaceBrightness,
        lightInfluence = Common.shared.lightInfluence,
        maxDistance = Common.shared.renderRange,
    },
    Mesh3D = {
        bonePaletteLimit = 'Requested bones per draw (1..32). Triangles keep all required '
            .. 'joints; smaller palettes may add draws.',
        effectiveBonePaletteLimit = 'Largest palette used; may exceed the request to preserve '
            .. 'an indivisible triangle.',
        lightInfluence = Common.shared.lightInfluence,
        maxBoneInfluences = 'Strongest weights retained per vertex (1..8), then normalized. '
            .. 'Imported data stays intact.',
        maxDistance = Common.shared.renderRange,
        skinDrawCount = 'Draw pieces after applying skin limits.',
    },
    SurfaceAppearance3D = {
        transparency = 'Material blend weight is 1-Transparency; active weights are normalized. '
            .. 'Mesh opacity remains separate.',
    },
}
