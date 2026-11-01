local descriptions = {
    Camera3D = {
        projectionMode = {
            options = { 'Perspective', 'Orthographic' },
            hint = 'Perspective shrinks distant objects; Orthographic keeps a constant scale.',
        },
        fov = {
            min = 1,
            max = 179,
            visibleWhen = { key = 'projectionMode', equals = 'Perspective' },
            hint = 'Vertical field of view in degrees. Linked to focalLength.',
        },
        orthoSize = {
            min = 0.001,
            visibleWhen = { key = 'projectionMode', equals = 'Orthographic' },
            hint = 'Half of the visible height in world units; width follows the aspect ratio.',
        },
        near = { min = 0.001, hint = 'Near clip distance; must be below far.' },
        far = { min = 0.002, hint = 'Far clip distance; must be above near.' },
    },
    Body3D = {
        mass = {
            get = function(node)
                return node.mass or node.body and node.body:getMass()
            end,
            min = 0.00001,
            hint = 'Mass in kg. Shows density-derived mass until an explicit override is authored; effective only for dynamic bodies.',
        },
        density = { min = 0.00001 },
    },
    ImageLabel = {
        tileSize = { visibleWhen = { key = 'fitMode', equals = 'Tile' } },
        tileOffset = { visibleWhen = { key = 'fitMode', equals = 'Tile' } },
    },
    Button = {
        imageColor = { visibleWhen = { key = 'image', present = true } },
        imageTransparency = { visibleWhen = { key = 'image', present = true } },
        fitMode = { visibleWhen = { key = 'image', present = true } },
        pixel = { visibleWhen = { key = 'image', present = true } },
        tileSize = {
            visibleWhen = {
                { key = 'image', present = true },
                {
                    key = 'fitMode',
                    equals = 'Tile',
                },
            },
        },
        tileOffset = {
            visibleWhen = {
                { key = 'image', present = true },
                {
                    key = 'fitMode',
                    equals = 'Tile',
                },
            },
        },
    },
    Decal3D = {
        textureSize = { visibleWhen = { key = 'mode', equals = 'Texture' } },
        textureOffset = { visibleWhen = { key = 'mode', equals = 'Texture' } },
        fitMode = { visibleWhen = { key = 'mode', equals = 'Tiles' } },
        tileSize = {
            visibleWhen = {
                { key = 'mode', equals = 'Tiles' },
                {
                    key = 'fitMode',
                    equals = 'Tile',
                },
            },
        },
        tileOffset = {
            visibleWhen = {
                { key = 'mode', equals = 'Tiles' },
                {
                    key = 'fitMode',
                    equals = 'Tile',
                },
            },
        },
        canvasPixelsPerUnit = {
            visibleWhen = {
                { key = 'mode', equals = 'Tiles' },
                { key = 'fitMode', equals = 'Tile' },
            },
        },
        imageOffset = { visibleWhen = { key = 'mode', equals = 'Decal' } },
    },
}

return descriptions
