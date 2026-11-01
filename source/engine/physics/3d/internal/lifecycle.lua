local ipairs = require('source.engine.math.array').ipairs
local Lifecycle = {}

function Lifecycle.install(Physics, Body3D)
    function Body3D:destroy()
        if self.destroyed then
            return
        end
        self.destroyed = true
        if self.physics._stepping or self.physics._flushing or self.physics._querying then
            self.physics.pendingRemoves[#self.physics.pendingRemoves + 1] = self
        elseif self._inWorld then
            self.physics.world:removeRigidBody(self.raw)
            self._inWorld = false
        end
        self.physics.triggerBodies[self] = nil
        self._renderPose = nil
        self.contacts, self._contactSets, self.overlaps, self._overlapScratch = {}, nil, nil, nil
        self.object.body = nil
        self.object.physicsMatrix = nil
        for i, b in ipairs(self.physics.bodies) do
            if b == self then
                table.remove(self.physics.bodies, i)
                break
            end
        end
    end

    function Physics:flushBodyChanges()
        self._flushing = true
        for _, body in ipairs(self.pendingRemoves) do
            if body._inWorld then
                self.world:removeRigidBody(body.raw)
                body._inWorld = false
            end
        end
        for _, body in ipairs(self.pendingAdds) do
            if not body.destroyed then
                self.world:addRigidBody(body.raw)
                body._inWorld = true
            end
        end
        for i = #self.pendingRemoves, 1, -1 do
            self.pendingRemoves[i] = nil
        end
        for i = #self.pendingAdds, 1, -1 do
            self.pendingAdds[i] = nil
        end
        self._flushing = false
        local queue = self.pendingColliderChanges
        if queue and #queue > 0 then
            -- Detach before callbacks: reentrant requests belong to the next flush.
            self.pendingColliderChanges = nil
            for _, request in ipairs(queue) do
                if not request.body.destroyed then
                    request.body:_applyCollider(request.candidate)
                end
            end
        end
        local settings = self.pendingSettings
        if settings and #settings > 0 then
            -- Detach before callbacks: reentrant requests belong to the next flush.
            self.pendingSettings = nil
            for _, request in ipairs(settings) do
                if not request.body.destroyed then
                    request.body:set(request.values)
                end
            end
        end
        local poses = self.pendingPoses
        if poses and #poses > 0 then
            -- Detach before callbacks: reentrant requests belong to the next flush.
            self.pendingPoses = nil
            for _, request in ipairs(poses) do
                if not request.body.destroyed then
                    request.body:teleport(request.position, request.rotation)
                end
            end
        end
        if self._releasePending then
            self._releasePending = nil
            self:release()
        end
    end

    function Physics:release()
        if self.released then
            return
        end
        if self._stepping or self._flushing or self._querying then
            self._releasePending = true
            return
        end
        -- Bodies and their joints must leave the solver before its native
        -- callbacks and world handles are freed by the adapter.
        while #self.bodies > 0 do
            self.bodies[#self.bodies]:destroy()
        end
        self._triggerState = nil
        self.triggerBodies = {}
        self.adapter:release()
        self.driver = nil -- Legacy native diagnostics alias.
        self.pendingAdds, self.pendingRemoves, self.pendingSettings, self.pendingPoses, self.pendingColliderChanges =
            {}, {}, nil, nil, nil
        self.released = true
    end
end

return Lifecycle
