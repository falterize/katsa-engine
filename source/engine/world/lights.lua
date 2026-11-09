local Layering = require('../components.layering')
local unpack = require('../math.array').unpack
local ipairs = require('../math.array').ipairs
local pairs = require('../math.array').pairs
local M = require('../math.math3d')

local Lights = {}
Lights.__index = Lights

local function nearer(a, b)
    local ad, bd = a.type == 'DirectionalLight3D', b.type == 'DirectionalLight3D'
    if ad ~= bd then
        return ad
    end
    if ad and (a.priority or 0) ~= (b.priority or 0) then
        return (a.priority or 0) > (b.priority or 0)
    end
    if a.selectionDistance ~= b.selectionDistance then
        return a.selectionDistance < b.selectionDistance
    end
    return a._selectionOrder < b._selectionOrder
end
local readValue = require('../math.managedValue').read

local function inputsChanged(self, light, save)
    local p, d, c =
        readValue(light.worldPosition), readValue(light.worldDirection), readValue(light.color)
    local old = self.uploadedInputs[light]
    if save then
        old = old or {}
        self.uploadedInputs[light] = old
        old[1], old[2], old[3] = p[1], p[2], p[3]
        old[4], old[5], old[6] = d[1], d[2], d[3]
        old[7], old[8], old[9] = c[1], c[2], c[3]
        old[10], old[11], old[12], old[13], old[14], old[15] = light.range,
            light.radius,
            light.brightness,
            light.type,
            light.rainbow,
            light.fogClearing
        return true
    end
    return not old
        or old[1] ~= p[1]
        or old[2] ~= p[2]
        or old[3] ~= p[3]
        or old[4] ~= d[1]
        or old[5] ~= d[2]
        or old[6] ~= d[3]
        or old[7] ~= c[1]
        or old[8] ~= c[2]
        or old[9] ~= c[3]
        or old[10] ~= light.range
        or old[11] ~= light.radius
        or old[12] ~= light.brightness
        or old[13] ~= light.type
        or old[14] ~= light.rainbow
        or old[15] ~= light.fogClearing
end

function Lights.new()
    local self = setmetatable({
        uploadedInputs = setmetatable({}, { __mode = 'k' }),
        selected = {},
        candidates = {},
        winners = {},
        slotOwners = {},
        relevantUntil = setmetatable({}, { __mode = 'k' }),
        nextSelection = 0,
        position = {},
        direction = {},
        color = {},
        extra = {},
    }, Lights)
    for i = 1, 32 do
        self.position[i] = { 0, 0, 0, 1 }
        self.direction[i] = { 0, 0, 1, 0 }
        self.color[i] = { 0, 0, 0, 0 }
        self.extra[i] = { 0, 0, 0, 0 }
    end
    return self
end

function Lights:update(world, camera, visible, time, dependencies)
    self.poseUpdates = 0
    for _, light in ipairs(world.lights) do
        local snapshot = dependencies and dependencies.meshSnapshots and dependencies.nodes[light]
        if
            not snapshot
            or snapshot.chainChanged
            or dependencies.refreshMeshes
            or not light._preparedLightPose
        then
            local matrix = light:getRenderWorldMatrix()
            light.worldPosition[1], light.worldPosition[2], light.worldPosition[3] =
                matrix[4], matrix[8], matrix[12]
            light.worldDirection[1], light.worldDirection[2], light.worldDirection[3] =
                M.normalize(matrix[3], matrix[7], matrix[11])
            light._preparedLightPose = true
            self.poseUpdates = self.poseUpdates + 1
        end
    end
    local settings = world.lighting.lightSettings
    local limit = math.max(0, math.min(32, math.floor(settings.maxActiveLights)))
    if time >= self.nextSelection or self.limit ~= limit then
        self.selectionRevision = (self.selectionRevision or 0) + 1
        self.holdingUntil = nil
        self.nextSelection = time + 1 / math.max(0.01, settings.selectionHz)
        self.limit = limit
        local candidates = self.candidates
        for i = #candidates, 1, -1 do
            candidates[i] = nil
        end
        for order, l in ipairs(world.lights) do
            l._selectionOrder = order
            local directional = l.type == 'DirectionalLight3D'
            l.eligible = false
            local relevant = directional or not settings.cullInvisible
            if
                l.enabled
                and l:isVisible()
                and (directional or l.range > 0)
                and Layering.sees(camera, l)
            then
                if not relevant then
                    for _, o in ipairs(visible) do
                        if
                            M.distanceSquared(
                                l.worldPosition or l.position,
                                (o.worldPosition or o.position)
                            )
                            <= (l.range + o.radius + 0.01) ^ 2
                        then
                            relevant = true
                            break
                        end
                    end
                end
                -- Visibility has a short exit hold; selectionBias supplies a
                -- distance-ranking entry/exit margin shared by all light types.
                if relevant then
                    self.relevantUntil[l] = time + (settings.selectionHoldSeconds or 0.4)
                elseif l.selected and time < (self.relevantUntil[l] or 0) then
                    self.holdingUntil = math.max(self.holdingUntil or 0, self.relevantUntil[l])
                    relevant = true
                end
                l.eligible = relevant
                if relevant then
                    l.selectionDistance = directional and 0
                        or M.distanceSquared(
                                l.worldPosition or l.position,
                                (camera.worldPosition or camera.position)
                            )
                            * (l.selected and (1 - math.max(
                                0,
                                math.min(0.9, settings.selectionBias or 0.1)
                            )) ^ 2 or 1)
                    candidates[#candidates + 1] = l
                end
            end
        end
        table.sort(candidates, nearer)
        -- Keep surviving winners in their previous GPU slots. Distance ranking
        -- chooses membership, not a new slot order on every camera movement.
        local winners = self.winners
        for light in pairs(winners) do
            winners[light] = nil
        end
        for i = 1, math.min(limit, #candidates) do
            winners[candidates[i]] = true
        end
        for _, light in ipairs(world.lights) do
            light.selected = false
        end
        local count = 0
        for _, light in ipairs(self.selected) do
            if winners[light] then
                count = count + 1
                self.selected[count], light.selected = light, true
            end
        end
        for _, light in ipairs(candidates) do
            if winners[light] and not light.selected then
                count = count + 1
                self.selected[count], light.selected = light, true
            end
        end
        for i = #self.selected, count + 1, -1 do
            self.selected[i] = nil
        end
    end
    local count = 0
    self.pending = false
    self.pendingUntil = nil
    for _, l in ipairs(self.selected) do
        if l.enabled and not l.destroyed and l:isVisible() then
            count = count + 1
            local hz = M.distanceSquared(
                l.worldPosition or l.position,
                (camera.worldPosition or camera.position)
            ) < settings.nearDistance ^ 2 and settings.nearUpdateHz or settings.farUpdateHz
            if
                l.type == 'DirectionalLight3D'
                or l.forceUpdate
                or time >= (l.nextUpdate or 0)
                or l.slot ~= count
                or self.slotOwners[count] ~= l
            then
                l.nextUpdate = time + 1 / math.max(hz, 0.01)
                l.slot = count
                local changed = self.slotOwners[count] ~= l or inputsChanged(self, l, false)
                self.slotOwners[count] = l
                if changed then
                    local p, d, c, e =
                        self.position[count],
                        self.direction[count],
                        self.color[count],
                        self.extra[count]
                    p[1], p[2], p[3], p[4] =
                        l.worldPosition[1],
                        l.worldPosition[2],
                        l.worldPosition[3],
                        l.type == 'DirectionalLight3D' and 0 or l.range
                    d[1], d[2], d[3] = unpack(l.worldDirection)
                    d[4] = l.range / math.sqrt(l.range ^ 2 + l.radius ^ 2)
                    c[1], c[2], c[3], c[4] =
                        l.color[1] / 255,
                        l.color[2] / 255,
                        l.color[3] / 255,
                        math.max(0, l.brightness)
                    e[1] = l.type == 'PointLight3D' and math.min(l.radius / l.range, 1)
                        or l.range / math.sqrt(l.range ^ 2 + l.radius ^ 2 * 0.5625)
                    e[2], e[3], e[4] =
                        l.type == 'DirectionalLight3D' and 2 or l.type == 'PointLight3D' and 1 or 0,
                        l.rainbow and 1 or 0,
                        l.type == 'DirectionalLight3D' and 0 or l.fogClearing
                    -- Commit only after successful preparation so invalid edits retry.
                    inputsChanged(self, l, true)
                end
            elseif inputsChanged(self, l, false) then
                self.pending = true
                self.pendingUntil = math.min(self.pendingUntil or math.huge, l.nextUpdate or time)
            end
        end
    end
    self.count = count
end

function Lights:send(shader)
    if shader:hasUniform('lightCount') then
        shader:send('lightCount', self.count)
    end
    if self.count > 0 then
        if shader:hasUniform('lightPosition') then
            shader:send('lightPosition', unpack(self.position, 1, self.count))
        end
        if shader:hasUniform('lightDirection') then
            shader:send('lightDirection', unpack(self.direction, 1, self.count))
        end
        if shader:hasUniform('lightColor') then
            shader:send('lightColor', unpack(self.color, 1, self.count))
        end
        if shader:hasUniform('lightExtra') then
            shader:send('lightExtra', unpack(self.extra, 1, self.count))
        end
    end
end

return Lights
