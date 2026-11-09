-- Settings the pathfinding plugin adds to every Body3D, read by NavMap3D baking.
return {
    properties = {
        navWalkable = {
            default = true,
            hint = 'NavMap3D baking takes this collider into account. Turn off to ignore it '
                .. '(a trigger volume, a decoration, a moving platform).',
        },
        navFloor = {
            default = 0,
            min = 0,
            hint = 'The NavMap3D floor this collider is the ground of. 0 or 1 = the first floor; '
                .. 'ramps, decks and other upper storeys use 2, 3...',
        },
    },
}
