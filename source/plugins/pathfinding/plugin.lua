return {
    name = 'pathfinding',
    title = 'Pathfinding',
    version = '1.2.0',
    description = 'A* search on grids, waypoint graphs and multi-floor maps, path smoothing and '
        .. 'following, the NavMap node and a navigation debug view.',
    requires = {},
    -- Enabled per scene with `plugins = { 'pathfinding' }` in the scene settings.
    nodes = { NavMap = './nodes.navMap' },
    extend = { Body3D = './extensions.body3D' },
    -- Two independent switches: the baked grid (cells and floor links) and the routes (every
    -- NavMap's recent paths plus the routes games report with Debug.setRoute).
    debug = {
        {
            key = 'pathfinding',
            title = 'Pathfinding grid',
            defaults = { enabled = false, drawCells = true, drawLinks = true, drawDistance = 40 },
            draw = './debug',
        },
        {
            key = 'pathfindingPaths',
            title = 'Pathfinding paths',
            defaults = { enabled = false },
            draw = './pathsDebug',
        },
    },
}
