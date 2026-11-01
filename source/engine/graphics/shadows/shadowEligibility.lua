local ipairs = require('source.engine.math.array').ipairs
local Math = require('source.engine.math.math3d')
local Receivers = require('source.engine.graphics.shadows.shadowReceivers')
local Types = require('source.engine.graphics.shadows.sourceTypes')
local kind, faces, pointDirections = Types.kind, Types.faces, Types.pointDirections
local viewProjection = require('source.engine.graphics.shadows.shadowProjection')

local Eligibility = {}

function Eligibility.prepare(self, settings, force, due, distanceChanged, hasReceivers)
    local hasPending = false
    for _, record in ipairs(self.assignments) do
        record.facesDirty = record.facesDirty or {}
        record.facesValid = record.facesValid or {}
        record.faceVisible = record.faceVisible or {}
        record.faceProjections = record.faceProjections or {}
        if force or record.lightChanged then
            record.projectionRevision = (record.projectionRevision or 0) + 1
        end
        local faceCount = faces(record)
        record.cost = 0
        local eligibilityChanged = force
            or distanceChanged
            or record.distanceChanged
            or record.lightChanged
            or record.receiverRevision ~= self.receiverRevision
            or record.visibleFacesOnly ~= settings.visibleFacesOnly
        record.receiverRevision, record.visibleFacesOnly =
            self.receiverRevision, settings.visibleFacesOnly
        if record.dirty and (due or force) then
            for face = 1, faceCount do
                record.facesDirty[face] = true
                if force then
                    record.facesValid[face] = false
                end
            end
            record.republish = true
            record.dirty = false
        end
        for face = 1, faceCount do
            local eligible = record.faceVisible[face] or false
            if record.kind == 2 then
                eligible = hasReceivers
            elseif eligibilityChanged then
                eligible = false
                if hasReceivers and record.inDistance and record.light.range > settings.near then
                    local saved = record.faceProjections[face]
                    if not saved then
                        saved = { matrix = Math.identity() }
                        record.faceProjections[face] = saved
                    end
                    local candidate = saved.matrix
                    if saved.revision ~= record.projectionRevision then
                        viewProjection.install(
                            record.light.worldPosition,
                            record.kind == 1 and pointDirections[face]
                                or record.light.worldDirection,
                            record.kind == 1 and 1
                                or math.max(0.001, record.light.radius / record.light.range),
                            settings.near,
                            record.light.range,
                            false,
                            candidate,
                            self.view,
                            self.projection
                        )
                        saved.revision = record.projectionRevision
                    end
                    eligible = hasReceivers
                        and (
                            settings.visibleFacesOnly == false
                            or (
                                Receivers.faceNeeded(candidate, self.receivers)
                                and Receivers.overlaps(candidate, self.receiverCorners)
                            )
                        )
                end
            end
            record.faceVisible[face] = eligible
            if eligible and record.facesDirty[face] then
                record.cost = record.cost + 1
            end
            if not eligible then
                self.skippedFaces = self.skippedFaces + 1
            end
        end
        if record.cost > 0 then
            hasPending = true
        end
        local data = self.lightData[record.light.slot]
        data[3] = 0
        for face = 1, faceCount do
            if record.facesValid[face] then
                data[3] = data[3] + 2 ^ (face - 1)
            end
        end
        data[1] = (data[3] > 0 and record.inDistance) and record.base or -1
    end
    return hasPending
end

return Eligibility
