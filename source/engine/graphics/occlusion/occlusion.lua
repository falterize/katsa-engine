local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
local Projection = require('source.engine.graphics.occlusion.projection')
local Occluders = require('source.engine.graphics.occlusion.occluders')
local Triangles = require('source.engine.graphics.occlusion.triangles')
local Validate = require('source.engine.core.validate')
local Coverage = require('source.engine.graphics.occlusion.coverage')
local Visibility = require('source.engine.graphics.occlusion.visibilityCache')

local Occlusion = {}

local function filter(renderer, list, camera, polygons, rect)
    local count, stats = 0, renderer.stats
    for _, object in ipairs(list) do
        local hidden = false
        if object:isA('Mesh3D') and not object.onTop then
            local record = Visibility.get(renderer.occlusionState, object, polygons)
            if record then
                hidden = record.hidden
                if record.mesh then
                    renderer.occlusionMeshes[object] = record.mesh
                    stats.occlusionPartialObjects = stats.occlusionPartialObjects + 1
                    stats.occlusionPartialTriangles = stats.occlusionPartialTriangles
                        + record.triangles
                end
                stats.occlusionReusedObjects = stats.occlusionReusedObjects + 1
            else
                -- Candidate collection already validated these bounds in this
                -- prepare phase. No user updates run between collection/filter.
                local state = renderer.occlusionState
                local cached = state.bounds[object]
                local projected
                if cached and cached.queryEpoch == state.boundsEpoch then
                    if cached.valid then
                        projected = cached.rect
                    end
                else
                    projected = Projection.bounds(object, camera, rect, state)
                end
                if projected then
                    local before = stats.occlusionPartialTriangles
                    local points = renderer.occlusionState.rectPoints or {}
                    renderer.occlusionState.rectPoints = points
                    points[1], points[2], points[3], points[4] =
                        projected[1], projected[2], projected[3], projected[2]
                    points[5], points[6], points[7], points[8] =
                        projected[3], projected[4], projected[1], projected[4]
                    stats.occlusionTests = stats.occlusionTests + #polygons
                    hidden = Coverage.test(
                        points,
                        projected[5],
                        polygons,
                        object,
                        renderer.occlusionState
                    )
                    local mesh
                    if not hidden then
                        mesh = Triangles.filter(
                            object,
                            camera,
                            polygons,
                            projected,
                            renderer.occlusionState,
                            stats
                        )
                        if mesh == false then
                            hidden = true
                            mesh = nil
                        end
                        if mesh then
                            renderer.occlusionMeshes[object] = mesh
                        end
                    end
                    Visibility.save(
                        renderer.occlusionState,
                        object,
                        polygons,
                        hidden,
                        mesh,
                        stats.occlusionPartialTriangles - before
                    )
                end
            end
        end
        if hidden then
            stats.occlusionCulled = stats.occlusionCulled + 1
        else
            count = count + 1
            list[count] = object
        end
    end
    for i = #list, count + 1, -1 do
        list[i] = nil
    end
end

function Occlusion.apply(renderer, camera)
    local stats = renderer.stats
    stats.occlusionCulled, stats.occlusionTests, stats.occlusionMilliseconds = 0, 0, 0
    stats.occlusionOccluders, stats.occlusionTrianglesTested = 0, 0
    stats.occlusionPartialTriangles, stats.occlusionPartialObjects, stats.occlusionTargetTrianglesTested =
        0, 0, 0
    stats.occlusionGeometryReused, stats.occlusionReusedObjects = false, 0
    renderer.occlusionMeshes = renderer.occlusionMeshes or {}
    for object in pairs(renderer.occlusionMeshes) do
        renderer.occlusionMeshes[object] = nil
    end
    if renderer.occlusionState then
        Triangles.prune(renderer.occlusionState)
    end
    -- Software occlusion projects with a perspective divide; orthographic views skip it.
    if not renderer.occlusionCulling or renderer.worldDebugWire or camera.orthographic then
        return
    end
    Validate.number(renderer.occlusionMaxOccluders, 'Render.occlusionMaxOccluders', 1, 1024)
    Validate.number(renderer.occlusionTriangleBudget, 'Render.occlusionTriangleBudget', 1, 4096)
    Validate.number(renderer.occlusionMinArea, 'Render.occlusionMinArea', 0)
    assert(
        renderer.occlusionMaxOccluders == math.floor(renderer.occlusionMaxOccluders),
        'Render.occlusionMaxOccluders must be an integer'
    )
    assert(
        renderer.occlusionTriangleBudget == math.floor(renderer.occlusionTriangleBudget),
        'Render.occlusionTriangleBudget must be an integer'
    )
    local start = katsa.timer.getTime()
    renderer.occlusionState = renderer.occlusionState or { rect = {} }
    local state = renderer.occlusionState
    if not state.maskSources then
        Triangles.prune(state)
    end
    state.unionBudget = 1024
    state.maskByteLimit = math.min(16777216, renderer.maxRenderBytes / 4)
    state.targetBudget = 8192 -- Unchecked triangles remain visible; this bounds CPU work.
    Projection.begin(state, camera)
    local polygons, work = Occluders.collect(renderer.opaque, camera, renderer, state)
    stats.occlusionOccluders, stats.occlusionTrianglesTested = #polygons, work
    stats.occlusionGeometryReused = state.geometryReused
    if #polygons == 0 then
        stats.occlusionMilliseconds = (katsa.timer.getTime() - start) * 1000
        return
    end
    filter(renderer, renderer.opaque, camera, polygons, state.rect)
    filter(renderer, renderer.transparent, camera, polygons, state.rect)
    stats.occlusionMilliseconds = (katsa.timer.getTime() - start) * 1000
end

return Occlusion
