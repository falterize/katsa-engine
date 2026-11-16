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
    LODGroup = {
        mode = 'Distance switches by camera distance in world units; ScreenSize by how tall the '
            .. 'group looks (fraction of the screen height).',
        distances = 'Where each next level starts, comma separated (for example 25, 60, 150): '
            .. 'level 1 from 25, level 2 from 60, hidden beyond 150. Empty or 0 entries use '
            .. 'defaults from the group radius.',
        screenSizes = 'Screen height fraction below which each next level starts, comma separated, '
            .. 'falling (for example 0.3, 0.1, 0.02); one more entry hides the group below it. '
            .. 'Empty or 0 entries use defaults.',
        bias = 'Above 1 lowers the detail sooner (weak devices), below 1 keeps it longer.',
        hysteresis = 'A finer level returns only after passing its switch point by this '
            .. 'fraction, so a group on the border does not flicker.',
        radius = 'Size of the group for the defaults and for ScreenSize; 0 measures level 0.',
        forceLevel = 'Pins one level (0 = most detailed); -1 chooses by the camera.',
        level = 'The level shown now; -1 when the whole group is hidden.',
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
