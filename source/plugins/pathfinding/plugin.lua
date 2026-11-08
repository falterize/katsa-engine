return {
    name = 'pathfinding',
    title = 'Pathfinding',
    version = '1.3.0',
    description = 'A* search on grids, waypoint graphs and multi-floor maps, path smoothing and '
        .. 'following, the NavMap node and a navigation debug view.',
    requires = {},
    -- Enabled per scene with `plugins = { 'pathfinding' }` in the scene settings.
    nodes = { NavMap = './nodes.navMap' },
    extend = { Body3D = './extensions.body3D' },
    -- One section, like Physics3D: `enabled` plus the parts to draw (baked cells, floor links,
    -- routes: every NavMap's recent paths and the routes games report with Debug.setRoute).
    debug = {
        key = 'pathfinding',
        title = 'Pathfinding',
        keys = { 'enabled', 'drawCells', 'drawLinks', 'drawPaths', 'drawDistance' },
        defaults = {
            enabled = false,
            drawCells = true,
            drawLinks = true,
            drawPaths = true,
            drawDistance = 40,
        },
        draw = './debug',
    },
}
