local bodyOf = require('source.engine.physics.bodyOf')
local descriptions = {
    Camera3D = {
        projectionMode = {
            options = { 'Perspective', 'Orthographic' },
        },
        fov = {
            min = 1,
            max = 179,
            visibleWhen = { key = 'projectionMode', equals = 'Perspective' },
        },
        orthoSize = {
            min = 0.001,
            visibleWhen = { key = 'projectionMode', equals = 'Orthographic' },
        },
        zoom = {
            min = 0.01,
            visibleWhen = { key = 'projectionMode', equals = 'Orthographic' },
        },
        orthoNear = {
            visibleWhen = { key = 'projectionMode', equals = 'Orthographic' },
        },
        near = {
            min = 0.001,
            visibleWhen = { key = 'projectionMode', equals = 'Perspective' },
        },
        far = { min = 0.002 },
    },
    Body3D = {
        mass = {
            get = function(node)
                return node.mass or bodyOf(node) and bodyOf(node):getMass()
            end,
            min = 0.00001,
        },
        density = { min = 0.00001 },
    },
    ImageRect = {
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
