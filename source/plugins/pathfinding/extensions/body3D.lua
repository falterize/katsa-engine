-- Settings the pathfinding plugin adds to every Body3D, read by NavMap baking.
return {
    properties = {
        navWalkable = {
            default = true,
            hint = 'NavMap baking takes this collider into account. Turn off to ignore it '
                .. '(a trigger volume, a decoration, a moving platform).',
        },
        navFloor = {
            default = 0,
            min = 0,
            hint = 'The NavMap floor this collider is the ground of. 0 or 1 = the first floor; '
                .. 'ramps, decks and other upper storeys use 2, 3...',
        },
    },
}
