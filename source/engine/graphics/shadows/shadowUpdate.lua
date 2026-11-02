local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
local Math = require('../../math.math3d')
local Validate = require('../../core.validate')
local ShadowCache = require('./shadowCache')
local Schedule = require('./shadowSchedule')
local Receivers = require('./shadowReceivers')
local Types = require('./sourceTypes')
local kind, faces, pointDirections = Types.kind, Types.faces, Types.pointDirections
local Directional = require('./directionalShadows')
local Residency = require('./shadowResidency')
local Eligibility = require('./shadowEligibility')
local Task = require('./shadowTask')
local ShadowUpdate = {}

function ShadowUpdate.install(Shadows)
    function Shadows:update(world, camera, lights, time, receivers)
        local settings = world.lighting.shadows
        self.enabled = settings.enabled
        self.drawCalls, self.updatedFaces, self.updatedLights, self.triangles = 0, 0, 0, 0
        self.batchComparisons, self.batchMatrixRows, self.batchUploadedRows = 0, 0, 0
        self.buildMilliseconds = 0
        self.scanMilliseconds = 0
        self.casterTests, self.casterSubmissions = 0, 0
        self.oldestPendingSeconds = 0
        self.pendingFaces = self.pendingFaces or 0
        for tileIndex, owner in pairs(self.faceOwners) do
            if owner.destroyed then
                self.faceBatches[tileIndex]:release()
                self.faceBatches[tileIndex], self.faceOwners[tileIndex] = nil, nil
            end
        end
        if
            self.lastCasterCount ~= #world.objects
            or self.dependencies and self.dependencies.objectsChanged
        then
            for _, batches in pairs(self.faceBatches) do
                batches:pruneDestroyed()
            end
            self.lastCasterCount = #world.objects
        end
        if self.batches.pruneDestroyed then
            self.batches:pruneDestroyed()
        end
        if self.residents then
            for index, record in pairs(self.residents) do
                if record.light.destroyed then
                    self.residents[index] = nil
                end
            end
            for index = #self.assignments, 1, -1 do
                if self.assignments[index].light.destroyed then
                    table.remove(self.assignments, index)
                end
            end
        end
        if not self.enabled then
            self.wasEnabled = false
            return
        end
        Validate.number(
            settings.resolution,
            'Shadows.resolution',
            32,
            katsa.graphics.getSystemLimits().texturesize
        )
        assert(
            settings.resolution == math.floor(settings.resolution),
            'Shadows.resolution must be an integer'
        )
        Validate.number(settings.distance, 'Shadows.distance', 1)
        Validate.number(settings.near, 'Shadows.near', 0.001)
        Validate.number(settings.updateHz, 'Shadows.updateHz', 0.01)
        Validate.number(settings.bias, 'Shadows.bias', 0)
        Validate.number(settings.normalBias, 'Shadows.normalBias', 0)
        Validate.number(settings.strength, 'Shadows.strength', 0, 1)
        assert(
            settings.filterSamples == 1
                or settings.filterSamples == 4
                or settings.filterSamples == 9,
            'Shadows.filterSamples must be 1, 4 or 9'
        )
        Residency.prepare(self, world, lights, time, settings)
        local clock = katsa.timer.getTime()
        if clock < (self.lastTime or 0) then
            self.nextUpdate = 0
        end
        if self.lastHz and self.lastHz ~= settings.updateHz then
            self.nextUpdate = -1
        end
        self.lastHz = settings.updateHz
        local due, tolerance =
            Schedule.due(self.nextUpdate, clock, self.lastTime, settings.updateHz)
        self.lastTime = clock
        local nearChanged = self.lastNear ~= settings.near
        local distanceChanged = self.lastDistance ~= settings.distance
        local force = self.atlasInvalid
            or not self.wasEnabled
            or self.nextUpdate == 0
            or self.lastLayers ~= settings.layers
            or nearChanged
        if force then
            -- Reallocated/relocated depth storage and changed projection conventions
            -- cannot safely expose old tiles while the budgeted rebuild is pending.
            for _, record in ipairs(self.assignments) do
                record.valid = false
            end
        end
        self.wasEnabled, self.lastLayers, self.lastNear, self.lastDistance =
            true, settings.layers, settings.near, settings.distance
        for _, record in ipairs(self.assignments) do
            record.lightChanged = ShadowCache.lightChanged(record, settings.near)
            record.dirty = record.dirty or record.lightChanged or force
            if record.kind == 2 then
                record.dirty = Directional.prepare(self, record, camera, settings) or record.dirty
            end
            local p, c = record.light.worldPosition, camera.worldPosition or camera.position
            local inDistance = record.kind == 2
                or Math.distanceSquared(p, c) <= (settings.distance + record.light.range) ^ 2
            record.distanceChanged = record.inDistance ~= inDistance
            record.inDistance = inDistance
        end
        -- The maintenance clock must never leave an old animated pose shadowing
        -- a new color-pass pose. Only overlapping changed sources become dirty.
        local casterChanged = self.scannedOwner ~= world._renderDependencyOwner
            or self.scannedRevision ~= (world._shadowDependencyRevision or world._renderDependencyRevision)
            or not world._renderDependencyOwner
        local coherent = casterChanged
        for _, record in ipairs(self.assignments) do
            coherent = coherent or record.lightChanged or record.dirty
        end
        if due or force or coherent then
            local tracked = self.trackedResidents or {}
            self.trackedResidents = tracked
            for i = #tracked, 1, -1 do
                tracked[i] = nil
            end
            for _, record in pairs(self.residents) do
                if force then
                    record.valid = false
                    record.facesValid = {}
                    record.dirty = true
                end
                tracked[#tracked + 1] = record
            end
            if force or casterChanged then
                local scanStart = katsa.timer.getTime()
                self.cache:scan(
                    world._shadowObjects or world.objects,
                    tracked,
                    settings.layers,
                    self.dependencies
                )
                self.scanMilliseconds = (katsa.timer.getTime() - scanStart) * 1000
                self.scannedOwner, self.scannedRevision =
                    world._renderDependencyOwner,
                    (world._shadowDependencyRevision or world._renderDependencyRevision)
            end
        end
        local receiverChanged
        self.receivers, receiverChanged =
            Receivers.cachedCollect(self, receivers, camera, settings, world)
        local hasReceivers = self.receivers == nil or #self.receivers > 0
        local corners, viewChanged =
            Receivers.prepare(camera, settings.distance, self.receiverCorners, settings.normalBias)
        if (corners == nil) ~= (self.receiverCorners == nil) then
            viewChanged = true
        end
        self.receiverCorners = corners
        self.receiverRevision = (self.receiverRevision or 0)
            + ((viewChanged or receiverChanged) and 1 or 0)
        local hasPending = false
        self.skippedFaces = 0
        hasPending = Eligibility.prepare(
            self,
            settings,
            force,
            due or coherent,
            distanceChanged,
            hasReceivers
        )
        if not due and not force and not hasPending and not distanceChanged then
            return
        end
        if due or force then
            self.nextUpdate = Schedule.advance(self.nextUpdate, clock, tolerance, settings.updateHz)
        end
        local buildStart = katsa.timer.getTime()
        self.depthPassStarted = false
        local tasks = self.tasks
        for i = #tasks, 1, -1 do
            tasks[i] = nil
        end
        for _, record in ipairs(self.assignments) do
            if record.cost > 0 then
                record.since = record.since or clock
                tasks[#tasks + 1] = record
            end
        end
        table.sort(tasks, function(a, b)
            if a.since ~= b.since then
                return a.since < b.since
            end
            return a.base < b.base
        end)
        local budget = settings.maxUpdateFaces or 12
        Validate.number(budget, 'Shadows.maxUpdateFaces', 1, 195)
        assert(budget == math.floor(budget), 'Shadows.maxUpdateFaces must be an integer')
        local ordinary = 0
        for _, task in ipairs(tasks) do
            -- Layout/configuration rebuilds are published together instead of
            -- flashing invalid tiles over several low-frequency ticks. Normal dirty
            -- queues drain every render frame, independently of change-scan Hz.
            if force or task.cost <= budget or ordinary == 0 then
                Task.draw(self, task, world, settings, time, clock)
                budget = budget - task.cost
                ordinary = ordinary + 1
            end
        end
        self.pendingFaces = 0
        for _, record in ipairs(self.assignments) do
            if record.since then
                self.oldestPendingSeconds =
                    math.max(self.oldestPendingSeconds, clock - record.since)
            end
            local data = self.lightData[record.light.slot]
            data[3] = 0
            for face = 1, faces(record) do
                if record.facesValid[face] then
                    data[3] = data[3] + 2 ^ (face - 1)
                end
                if record.faceVisible[face] and record.facesDirty[face] then
                    self.pendingFaces = self.pendingFaces + 1
                end
            end
            data[1] = (
                data[3] > 0
                and record.inDistance
                and (record.kind == 2 or record.light.range > settings.near)
            )
                    and record.base
                or -1
        end
        if self.updatedFaces > 0 then
            if self.directionalMatricesChanged then
                self.matrixTexture:replacePixels(self.matrixPixels)
                self.directionalMatricesChanged = false
            end
            self.generation = self.generation + 1
        end
        if self.depthPassStarted then
            katsa.graphics.pop()
        end
        self.sourceCasters = nil
        for i = #self.casters, 1, -1 do
            self.casters[i] = nil
        end
        self.atlasInvalid = false
        self.buildMilliseconds = (katsa.timer.getTime() - buildStart) * 1000
    end
end

return ShadowUpdate
