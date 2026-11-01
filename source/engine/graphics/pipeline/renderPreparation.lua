local Frustum = require('source.engine.cameras.frustum')
local readValue = require('source.engine.math.managedValue').read
local unpack = require('source.engine.math.array').unpack
local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
-- Install one cohesive responsibility on the public class.
local M = require('source.engine.math.math3d')
local bit = require('bit')
local Occlusion = require('source.engine.graphics.occlusion.occlusion')
local Triangles = require('source.engine.graphics.debug.triangles')

local function clear(list)
    for i = #list, 1, -1 do
        list[i] = nil
    end
end

local function farFirst(a, b)
    if a.onTop and b.onTop and (a.zIndex or 0) ~= (b.zIndex or 0) then
        return (a.zIndex or 0) < (b.zIndex or 0)
    end
    if math.abs(a.depth - b.depth) < 0.001 and (a.zIndex or 0) ~= (b.zIndex or 0) then
        return (a.zIndex or 0) < (b.zIndex or 0)
    end
    return a.depth > b.depth
end
local RenderPreparation = {}

function RenderPreparation.install(Renderer)
    function Renderer:prepare(world, camera, time, dependencies)
        dependencies = dependencies
            or require('source.engine.graphics.pipeline.frameCache').inspect(
                self,
                world,
                camera,
                time,
                false
            )
        world._renderDependencyOwner = self
        world._renderDependencyRevision = dependencies.sceneRevision
        world._shadowDependencyRevision = dependencies.casterRevision
        for key, value in pairs(world.environment.render) do
            self[key] = value
        end
        Triangles.begin()
        local prepareStart = love.timer.getTime()
        self:resize(
            self.targetWidth or love.graphics.getWidth(),
            self.targetHeight or love.graphics.getHeight()
        )
        world:resolveLayerGroup(camera)
        world._materialCamera = camera
        world._activeRenderer = self
        world._renderResolving = true
        world._renderShaderNodes = world._renderShaderNodes or {}
        clear(world._renderShaderNodes)
        for _, node in ipairs(world.shaderNodes or {}) do
            if node.enabled ~= false and node.shaderPath ~= '' then
                table.insert(world._renderShaderNodes, node)
            end
        end
        local wire = world.debug and world.debug.wireframe
        camera:update(self.width, self.height)
        self._frustum = Frustum.capture(camera, self._frustum)
        local visible, cullState = Frustum.visible, self._frustum
        if camera.visible ~= Frustum.defaultVisible then
            visible, cullState = camera.visible, camera
        end
        clear(self.visible)
        clear(self.opaque)
        clear(self.transparent)
        clear(self.top)
        self.stats.distanceCulled = 0
        self.stats.updatedMeshes = 0
        for _, o in ipairs(world.objects) do
            local snapshot = dependencies.meshSnapshots and dependencies.nodes[o]
            if
                not snapshot
                or snapshot.chainChanged
                or dependencies.refreshMeshes
                or not o._preparedMesh
                or o._appearancePending and world.environment.shadows.enabled
            then
                if not wire then
                    require('source.engine.shaders.materialResolver').resolve(world, o)
                end
                local deferAppearance = not wire and not world.environment.shadows.enabled
                world:updateObject(o, true, wire or deferAppearance)
                o._appearancePending = deferAppearance
                if deferAppearance and (not o._renderVisible or o._renderOpacity <= 0) then
                    world:updateAppearance(o)
                    o._appearancePending = false
                end
                o._preparedMesh = true
                self.stats.updatedMeshes = self.stats.updatedMeshes + 1
            end
            local limit = o.maxDistance or 0
            if self.maxMeshDistance > 0 then
                limit = limit > 0 and math.min(limit, self.maxMeshDistance) or self.maxMeshDistance
            end
            local inDistance = limit <= 0
                or M.distanceSquared(
                        o.worldPosition or o.position,
                        camera.worldPosition or camera.position
                    )
                    <= (limit + o.radius) ^ 2
            if not inDistance then
                self.stats.distanceCulled = self.stats.distanceCulled + 1
            end
            if
                inDistance
                and o._renderVisible
                and bit.band(o.layers or 1, camera.layers or -1) ~= 0
                and o._renderOpacity > 0
                and (
                    o._shaderBoundsUnknown
                    or visible(
                        cullState,
                        o.worldPosition or o.position,
                        o.radius + (o._shaderBoundsPadding or 0)
                    )
                )
            then
                -- Resolve maps/blend canvases only after visibility rejection. Offscreen
                -- shadow casters retain the full path when shadow generation is enabled.
                if o._appearancePending then
                    world:updateAppearance(o)
                    o._appearancePending = false
                end
                self.visible[#self.visible + 1] = o
                local p = readValue(o.worldPosition or o.position)
                local _, _, z = M.transform(camera.view, p[1], p[2], p[3])
                o.depth = z
                local list = (
                    o._renderOpacity < 1
                    or o.blend
                    or o._surfaceBlend
                    or (readValue(o.color)[4] or 1) < 1
                )
                        and self.transparent
                    or self.opaque
                list[#list + 1] = o
            end
        end
        self.billboardDebugActive = false
        for _, b in ipairs(world.billboards) do
            world:resolveLayerGroup(b)
            b:update(world, camera)
            if not wire and b.drawable and b:refresh() then
                b:update(world, camera)
            end
            b.drawable = b.drawable and bit.band(b.layers or 1, camera.layers or -1) ~= 0
            if b.drawable then
                if b.debugEnabled then
                    self.billboardDebugActive = true
                end
                local list = b.onTop and self.top or self.transparent
                list[#list + 1] = b
            end
        end
        local receivers = self.visible
        clear(self.surfaceReceivers)
        for _, d in ipairs(world.decals) do
            if not wire then
                require('source.engine.shaders.materialResolver').resolve(world, d)
            end
            world:resolveLayerGroup(d)
            if wire then
                require('source.engine.surfaces.faces').update(d, camera)
            else
                d:update(world, camera)
            end
            if d.drawable and bit.band(d.layers or 1, camera.layers or -1) ~= 0 then
                local list = d.onTop and self.top or self.transparent
                list[#list + 1] = d
                if not d.unlit and not d.onTop then
                    if receivers == self.visible then
                        for i, object in ipairs(self.visible) do
                            self.surfaceReceivers[i] = object
                        end
                        receivers = self.surfaceReceivers
                    end
                    receivers[#receivers + 1] = d
                end
            end
        end
        if world.particles and not wire then
            local stats = world.particles.stats
            stats.drawCalls, stats.rendered, stats.meshBytes, stats.drawMilliseconds = 0, 0, 0, 0
            for _, emitter in ipairs(world.particles.emitters) do
                stats.meshBytes = stats.meshBytes + (emitter._meshCapacity or 0) * 6 * 9 * 4
                if
                    #emitter.particles > 0
                    and require('source.engine.particles.visibility').relevant(
                        emitter,
                        camera,
                        true
                    )
                then
                    local position = emitter:getWorldPosition()
                    emitter.depth = (position[1] - camera.worldPosition[1]) * camera.forward[1]
                        + (position[2] - camera.worldPosition[2]) * camera.forward[2]
                        + (position[3] - camera.worldPosition[3]) * camera.forward[3]
                    self.transparent[#self.transparent + 1] = emitter
                end
            end
        end
        table.sort(self.transparent, farFirst)
        table.sort(self.top, farFirst)
        self.stats.cullingMilliseconds = (love.timer.getTime() - prepareStart) * 1000
        if not wire and world.particles then
            self.shadowObjects = require('source.engine.particles.shadows').prepare(
                world,
                camera,
                self.shadowObjects
            )
            world._shadowObjects = self.shadowObjects
        end
        if self.shadowObjects and not wire then
            for _, proxy in ipairs(self.shadowObjects) do
                if proxy._particleCaster and proxy.receiveShadow then
                    if receivers == self.visible then
                        for i, o in ipairs(self.visible) do
                            self.surfaceReceivers[i] = o
                        end
                        receivers = self.surfaceReceivers
                    end
                    receivers[#receivers + 1] = proxy
                end
            end
        end
        local lightStart = love.timer.getTime()
        for _, light in ipairs(world.lights) do
            world:resolveLayerGroup(light)
        end
        if not wire then
            self.lights:update(world, camera, receivers, time, dependencies)
        end
        self.stats.lightSelectionMilliseconds = (love.timer.getTime() - lightStart) * 1000
        self.gizmos:update(world, self.lights, time)

        if wire then
            self.shadows.updatedFaces, self.shadows.drawCalls, self.shadows.casterTests, self.shadows.casterSubmissions =
                0, 0, 0, 0
            self.shadows.buildMilliseconds, self.shadows.scanMilliseconds, self.shadows.updatedLights =
                0, 0, 0
        end
        if not wire and not self.freezeShadowUpdates then
            self.shadows.dependencies = dependencies
            self.shadows:update(world, camera, self.lights, time, receivers)
        end
        if not wire and self.lightLoop == 'Masked' then
            require('source.engine.graphics.pipeline.lightMasks').update(self.visible, self.lights)
        end
        self.worldDebugWire = wire
        self.world = world
        self.stats.mainTriangles = 0
        self.stats.meshTrianglesBeforeOcclusion = Triangles.list(self.opaque)
            + Triangles.list(self.transparent)
        Occlusion.apply(self, camera)
        self.stats.meshTrianglesAfterOcclusion = Triangles.list(self.opaque, self.occlusionMeshes)
            + Triangles.list(self.transparent, self.occlusionMeshes)
        self.stats.occlusionSavedTriangles = self.stats.meshTrianglesBeforeOcclusion
            - self.stats.meshTrianglesAfterOcclusion
        if not wire then
            self.batches:prepare(self.opaque, dependencies, self.occlusionMeshes)
        end
        self.stats.shadowTriangles = (wire or self.freezeShadowUpdates) and 0
            or self.shadows.triangles
            or 0
        self.stats.shadowDrawCalls = self.shadows.drawCalls
        self.stats.shadowCasterTests = self.shadows.casterTests
        self.stats.shadowCasterSubmissions = self.shadows.casterSubmissions
        self.stats.shadowAtlasAllocations = self.shadows.atlasAllocations
        self.stats.shadowFaces = self.shadows.updatedFaces
        self.stats.shadowPendingFaces = wire and 0 or self.shadows.pendingFaces
        self.stats.shadowOldestMilliseconds = wire and 0
            or (self.shadows.oldestPendingSeconds or 0) * 1000
        self.stats.actualMSAA = self.actualMSAA
        self.stats.renderDensity = self.density
        self.stats.shadowSkippedFaces = self.shadows.skippedFaces or 0
        self.stats.shadowLights = self.shadows.updatedLights
        self.stats.shadowScanMilliseconds = self.shadows.scanMilliseconds
        self.stats.shadowBuildMilliseconds = self.shadows.buildMilliseconds
        self.stats.shadowDepthBytes = (self.shadows.resolution or 0) ^ 2
            * (self.shadows.columns or 0)
            * (self.shadows.rows or 0)
            * 4
        self.stats.objects = #self.visible
        world._renderResolving = false
        self.stats.lights = wire and 0 or self.lights.count
    end
end

return RenderPreparation
