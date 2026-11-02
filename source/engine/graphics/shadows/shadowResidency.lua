local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
local Types = require('source.engine.graphics.shadows.sourceTypes')
local kind, faces, pointDirections = Types.kind, Types.faces, Types.pointDirections
local Residency = {}

function Residency.prepare(self, world, lights, time, settings)
    -- Reserve six adjacent tiles per resident source. Membership changes reuse
    -- vacant/evicted slots without relocating surviving maps or resizing storage.
    self.residents = self.residents or {}
    local wanted = self.wanted or {}
    self.wanted = wanted
    for light in pairs(wanted) do
        wanted[light] = nil
    end
    local byLight = self.residentLookup or {}
    self.residentLookup = byLight
    for light in pairs(byLight) do
        byLight[light] = nil
    end
    for _, light in ipairs(lights.selected) do
        if light.enabled and not light.destroyed and light.castShadow ~= false then
            wanted[light] = true
        end
    end
    -- Size the atlas for the lights that actually cast shadows, not the global light cap: 32
    -- reserved point lights meant a 14336 x 14336 depth map (about 820 MB) even for two casters.
    -- Capacity grows in steps of four and only shrinks once demand falls below half of it.
    local limit = math.min(
        32,
        math.max(
            1,
            lights.limit
                or world.lighting.lightSettings and world.lighting.lightSettings.maxActiveLights
                or 32
        )
    )
    local demand = 0
    for _ in pairs(wanted) do
        demand = demand + 1
    end
    local capacity = math.min(limit, math.max(4, math.ceil(demand / 4) * 4))
    local previous = self.capacity
    if previous and previous <= limit and previous >= capacity and capacity * 2 > previous then
        capacity = previous
    end
    self.capacity = capacity
    for index, record in pairs(self.residents) do
        if record.light.destroyed or index > capacity then
            self.residents[index] = nil
        else
            byLight[record.light] = record
        end
    end
    for i = 1, 32 do
        local data = self.lightData[i]
        data[1], data[2], data[3] = -1, 0, 0
    end
    local count = 0
    for _, light in ipairs(lights.selected) do
        if wanted[light] then
            local record = byLight[light]
            if record and record.kind ~= kind(light) then
                record = {
                    light = light,
                    kind = kind(light),
                    base = record.base,
                    dirty = true,
                    valid = false,
                }
                self.residents[record.base / 6 + 1] = record
                byLight[light] = record
            end
            if not record then
                local vacant
                for index = 1, capacity do
                    if not self.residents[index] then
                        vacant = index
                        break
                    end
                end
                if not vacant then
                    for index = 1, capacity do
                        local resident = self.residents[index]
                        if
                            not wanted[resident.light]
                            and (not vacant or resident.lastUsed < self.residents[vacant].lastUsed)
                        then
                            vacant = index
                        end
                    end
                end
                assert(vacant, 'Shadow residency capacity exceeded')
                record = {
                    light = light,
                    kind = kind(light),
                    base = (vacant - 1) * 6,
                    dirty = true,
                    valid = false,
                    fadeIn = self.generation > 0,
                }
                self.residents[vacant] = record
                byLight[light] = record
            end
            record.lastUsed = time
            count = count + 1
            self.assignments[count] = record
            self.lightData[light.slot][2] = record.kind
        end
    end
    for i = #self.assignments, count + 1, -1 do
        self.assignments[i] = nil
    end
    local faceCount = capacity * 6
    self.localLightCount, self.faceCount = count, faceCount
    self:resize(settings.resolution, faceCount)
end

return Residency
