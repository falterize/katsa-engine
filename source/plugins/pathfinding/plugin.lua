return {
    name = 'pathfinding',
    title = 'Pathfinding',
    version = '1.5.0',
    description = 'A* search on grids, waypoint graphs and multi-floor maps, path smoothing and '
        .. 'following, a baked NavMesh with dynamic obstacles and crowds, the NavMap3D, NavAgent3D, '
        .. 'NavObstacle3D, NavLink3D and NavArea3D nodes and a navigation debug view.',
    requires = {},
    demoScene = 'navMeshLab',
    -- Enabled per scene with `plugins = { 'pathfinding' }` in the scene settings.
    nodes = {
        NavMap3D = './nodes.navMap3D',
        NavAgent3D = './nodes.navAgent3D',
        NavObstacle3D = './nodes.navObstacle3D',
        NavLink3D = './nodes.navLink3D',
        NavArea3D = './nodes.navArea3D',
    },
    extend = { Body3D = './extensions.body3D' },
    -- One section, like Physics3D: `enabled` plus the parts to draw (baked cells, floor links,
    -- routes: every NavMap3D's recent paths and the routes games report with Debug.setRoute).
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
