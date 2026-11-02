return {
    name = 'pathfinding',
    title = 'Pathfinding',
    version = '1.1.0',
    description = 'A* search on grids, waypoint graphs and multi-floor maps, path smoothing and '
        .. 'following, the NavMap node and a navigation debug view.',
    requires = {},
    -- Enabled per scene with `plugins = { 'pathfinding' }` in the scene settings.
    nodes = { NavMap = 'source.plugins.pathfinding.nodes.navMap' },
    extend = { Body3D = 'source.plugins.pathfinding.extensions.body3D' },
    debug = {
        key = 'pathfinding',
        title = 'Pathfinding',
        defaults = {
            enabled = false,
            drawCells = true,
            drawLinks = true,
            drawPaths = true,
            drawDistance = 40,
        },
        draw = 'source.plugins.pathfinding.debug',
    },
}
