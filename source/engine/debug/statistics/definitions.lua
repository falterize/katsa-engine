local Panel = require('source.engine.debug.statistics.panel')

local Statistics = {}
Statistics.__index = Statistics

local rendererFields = {
    { 'objects', 'Mesh candidates' },
    { 'lights', 'Light candidates' },
    { 'shadowDrawCalls', 'Shadow draw calls' },
    { 'shadowFaces', 'Shadow faces' },
    { 'shadowPendingFaces', 'Shadow pending faces' },
    { 'shadowOldestMilliseconds', 'Oldest pending shadow', 'ms' },
    { 'shadowSkippedFaces', 'Shadow skipped faces' },
    { 'shadowLights', 'Shadow sources' },
    { 'shadowBuildMilliseconds', 'Shadow CPU build', 'ms' },
    { 'shadowDepthBytes', 'Shadow atlas', 'MB', 1048576 },
    { 'cullingMilliseconds', 'Render preparation', 'ms' },
    { 'mainSubmissionMilliseconds', 'Main CPU submission', 'ms' },
    { 'cacheCheckMilliseconds', '3D cache checks', 'ms' },
    { 'reusedFrames', 'Reused frames' },
    { 'renderedFrames', 'Rendered frames' },
    { 'updatedMeshes', 'Updated meshes' },
    { 'cacheCheckAverageMilliseconds', 'Checks average (1s)', 'ms' },
    { 'cacheCheckMaxMilliseconds', 'Checks maximum (1s)', 'ms' },
    { 'scalarGroupsSkipped', 'Scalar groups reused' },
    { 'scalarGroupsChecked', 'Scalar groups checked' },
    { 'meshTrianglesBeforeOcclusion', 'Triangles before occlusion' },
    { 'meshTrianglesAfterOcclusion', 'Triangles after occlusion' },
    { 'occlusionSavedTriangles', 'Occlusion saved triangles' },
    { 'occlusionCulled', 'Occlusion whole objects' },
    { 'occlusionPartialObjects', 'Occlusion partial objects' },
    { 'occlusionMilliseconds', 'Occlusion CPU', 'ms' },
    { 'mainTriangles', 'Main submitted triangles' },
    { 'shadowTriangles', 'Shadow triangles' },
    { 'depthPrepassMilliseconds', 'Early depth CPU', 'ms' },
    { 'depthPrepassTriangles', 'Early depth triangles' },
    { 'depthPrepassDrawCalls', 'Early depth draws' },
}
local physicsFields = {
    { 'updateMilliseconds', 'Physics total', 'ms' },
    { 'solverMilliseconds', 'Physics solver/adapter', 'ms' },
    { 'nativeSolverMilliseconds', 'Native solver', 'ms' },
    { 'triggerMilliseconds', 'Physics triggers', 'ms' },
    { 'steps', 'Physics steps' },
    { 'triggerQueries', 'BVH queries' },
    { 'triggerCandidates', 'BVH candidates' },
    { 'triggerPairs', 'Exact trigger pairs' },
    { 'workerThreads', 'Configured workers' },
    { 'workerContactCallbacks', 'Worker contact callbacks' },
    { 'droppedTime', 'Dropped simulation time', 's' },
}

local function add(list, id, label, unit, read)
    list[#list + 1] = { id = id, label = label, unit = unit, read = read }
end

local function fields(list, prefix, entries, source)
    for _, entry in ipairs(entries) do
        local key, divisor = entry[1], entry[4] or 1
        add(list, prefix .. key, entry[2], entry[3], function(context)
            local values = source(context)
            return values and values[key] and values[key] / divisor
        end)
    end
end

function Statistics.new(scene, parent)
    local definitions = {}
    add(definitions, 'update.cpu', 'Scene update CPU', 'ms', function(c)
        return c.scene.manager.focused ~= false and c.scene.updateMilliseconds or nil
    end)
    add(definitions, 'ui.cpu.previous', 'Screen UI CPU (previous frame)', 'ms', function(c)
        return c.scene.uiMilliseconds
    end)
    add(definitions, 'fps', 'FPS', 'frames/s', function(c)
        local dt = c.scene.manager.frameDelta
        return dt > 0 and 1 / dt or nil
    end)
    definitions[#definitions].aggregation = 'rate'
    add(definitions, 'stats.visible', 'Stats visible', '0/1', function(c)
        return c.scene.showStats and 1 or 0
    end)
    add(definitions, 'frame.limit', 'Configured frame ceiling', 'frames/s', function(c)
        local scene = c.scene
        local limit = scene.settings.frameRateLimit
        return limit ~= nil and limit or require('source.engine.core.runtime').frameRateLimit or 0
    end)
    add(definitions, 'frame', 'Frame delta', 'ms', function(c)
        return c.scene.manager.frameDelta * 1000
    end)
    add(definitions, 'frame.gap', 'Between-frame wait / events', 'ms', function(c)
        return c.scene.manager.frameGapMilliseconds
    end)
    add(definitions, 'focus', 'Window focused', '0/1', function(c)
        return c.scene.manager.focused and 1 or 0
    end)
    add(definitions, 'scale', 'Simulation speed', 'x', function(c)
        return c.scene.manager.time.scale
    end)
    add(definitions, 'scale.world2D', 'World2D time scale', 'x', function(c)
        return c.scene.ui.timeScale
    end)
    add(definitions, 'scale.world3D', 'World3D time scale', 'x', function(c)
        return c.scene.world.root.timeScale
    end)
    add(definitions, 'drawcalls', 'Draw calls', nil, function(c)
        return c.graphics.drawcalls
    end)
    add(definitions, 'texture', 'Texture memory', 'MB', function(c)
        return c.graphics.texturememory / 1048576
    end)
    add(definitions, 'lua', 'Lua memory', 'MB', function()
        return collectgarbage('count') / 1024
    end)
    add(definitions, 'meshes', 'Scene meshes', nil, function(c)
        return #c.scene.world.objects
    end)
    add(definitions, 'lights', 'Scene lights', nil, function(c)
        return #c.scene.world.lights
    end)
    add(definitions, 'width', 'Render width', 'px', function(c)
        return c.scene.renderer.canvas and c.scene.renderer.canvas:getPixelWidth()
    end)
    add(definitions, 'height', 'Render height', 'px', function(c)
        return c.scene.renderer.canvas and c.scene.renderer.canvas:getPixelHeight()
    end)
    add(definitions, 'buffers', 'Instance buffer allocations', nil, function(c)
        return c.scene.renderer.batches.totalMeshAllocations
    end)
    add(definitions, 'variants', 'Shader variants', nil, function(c)
        return c.scene.renderer.shaderVariantCount
    end)
    add(definitions, 'early', 'Early depth active', '0/1', function(c)
        return c.scene.renderer.depthPrepassActive and 1 or 0
    end)
    add(definitions, 'reuse', '3D frame reused', '0/1', function(c)
        return c.scene.renderer.stats.frameReused and 1 or 0
    end)
    fields(definitions, 'render.', rendererFields, function(c)
        return c.scene.renderer.stats
    end)
    fields(definitions, 'physics.', physicsFields, function(c)
        local physics = c.scene.physics or c.scene.world.physics
        return c.scene.manager.focused ~= false and physics and physics.stats or nil
    end)
    fields(definitions, 'physics2D.', {
        { 'updateMilliseconds', '2D physics total', 'ms' },
        { 'solverMilliseconds', '2D Box2D solver', 'ms' },
        { 'steps', '2D physics steps' },
        { 'bodies', '2D bodies' },
        { 'fixtures', '2D fixtures' },
        { 'contacts', '2D contacts' },
        { 'joints', '2D joints' },
        { 'sleeping', '2D sleeping bodies' },
        { 'droppedTime', '2D dropped time', 's' },
    }, function(c)
        return c.scene.ui.physics2D and c.scene.ui.physics2D.stats
    end)
    fields(definitions, 'checks.', {
        { 'objects', 'Checks: meshes', 'ms' },
        { 'lights', 'Checks: point lights', 'ms' },
        { 'directionalLights', 'Checks: directional lights', 'ms' },
        { 'guards', 'Checks: guards', 'ms' },
        { 'shaderNodes', 'Checks: shaders', 'ms' },
        { 'other', 'Checks: other', 'ms' },
    }, function(c)
        return c.scene.renderer.stats.cacheCheckPhases
    end)
    fields(definitions, 'probe.', {
        { 'withoutSampling', 'Shadow A/B without sampling', 'ms' },
        { 'withSampling', 'Shadow A/B with sampling', 'ms' },
        { 'difference', 'Shadow A/B sampling delta', 'ms' },
        { 'buildDifference', 'Shadow A/B rebuild delta', 'ms' },
        { 'buildCPUMilliseconds', 'Shadow A/B rebuild CPU', 'ms' },
    }, function(c)
        return c.scene.shadowProbe
    end)
    fields(definitions, 'loop.', {
        { 'events', 'Loop events (previous frame)', 'ms' },
        { 'update', 'Loop update (previous frame)', 'ms' },
        { 'draw', 'Loop draw (previous frame)', 'ms' },
        { 'present', 'Loop present (previous frame)', 'ms' },
        { 'sleep', 'Loop sleep (previous frame)', 'ms' },
    }, function()
        return require('source.engine.core.runtime').timings
    end)
    for _, definition in ipairs(definitions) do
        local id = definition.id
        definition.background = id == 'fps'
            or id == 'frame'
            or id == 'focus'
            or id == 'stats.visible'
            or id == 'frame.limit'
            or id == 'update.cpu'
            or id == 'ui.cpu.previous'
            or id:sub(1, 5) == 'loop.'
    end
    local self = setmetatable(
        { scene = scene, graphics = {}, panel = Panel.new(scene.ui, parent, definitions) },
        Statistics
    )
    self.context = { scene = scene, graphics = self.graphics }
    return self
end

function Statistics:sample()
    local scene = self.scene
    if scene.showStats and scene.manager.frameTime >= self.panel.nextRefresh then
        katsa.graphics.getStats(self.graphics)
        local physics = scene.physics or scene.world.physics
        self.panel.exportMetadata = self.panel.exportMetadata or {}
        self.panel.exportMetadata.scene = scene.zone
        self.panel.exportMetadata.backend = (physics and physics.backendName or 'none')
            .. (scene.ui.physics2D and ' + Box2D (2D)' or '')
        self.panel.header.text = string.format(
            '%s | Physics: %s | requested: %s%s\nRuntime: %s (%s, %s) | Light loop: %s\nClick '
                .. 'any numeric row for history. %s',
            scene.zone,
            (physics and physics.backendName or 'none')
                .. (scene.ui.physics2D and ' + Box2D (2D)' or ''),
            scene.options.physicsBackend
                or (scene.options.physics or {}).backend
                or (scene.settings.physics or {}).backend
                or 'default',
            physics and physics.backendFallback and ' (auto fallback)' or '',
            jit and jit.version or _VERSION,
            jit and jit.status() and 'JIT ON' or 'JIT OFF',
            jit and jit.arch or 'Lua',
            scene.world.environment.render.lightLoop,
            scene.statsHelp or 'WASD + Q/E; drag to look.'
        )
    end
    self.panel:sample(self.context, scene.manager.frameTime, scene.showStats)
end

return Statistics
