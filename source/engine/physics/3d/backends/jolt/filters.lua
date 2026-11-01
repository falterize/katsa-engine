local Compatibility = require('source.engine.physics.3d.backends.oimo.compatibility')
local Library = require('source.engine.physics.3d.backends.jolt.library')
local bit = require('bit')

local C = Library.C

local Filters = {}

function Filters:refreshFilters(body)
    Compatibility.refreshFilters(self, body)
    if not body.raw._joltPtr then
        return
    end
    local groups, masks = self.physics.groups, self.physics.masks
    if self.filterRevision ~= self.physics.collisionGroups.revision then
        for aname, a in pairs(groups) do
            local ai = math.floor(math.log(a) / math.log(2) + 0.5)
            for name, b in pairs(groups) do
                local bi = math.floor(math.log(b) / math.log(2) + 0.5)
                local enabled = bit.band(a, masks[name]) ~= 0 and bit.band(b, masks[aname]) ~= 0
                if enabled then
                    C.JPH_ObjectLayerPairFilterTable_EnableCollision(self.pairs, ai, bi)
                else
                    C.JPH_ObjectLayerPairFilterTable_DisableCollision(self.pairs, ai, bi)
                end
            end
        end
        self.filterRevision = self.physics.collisionGroups.revision
        for raw in pairs(self.bodies) do
            C.JPH_BodyInterface_InvalidateContactCache(self.interface, raw._joltId)
            if raw._type ~= 1 then
                C.JPH_BodyInterface_ActivateBody(self.interface, raw._joltId)
            end
        end
    end
    local value = groups[body.group]
    local layer = math.floor(math.log(value) / math.log(2) + 0.5)
    if not body.canCollide or body.isTrigger or body.colliderEnabled == false then
        layer = layer + 32
    end
    if body.raw._joltLayer ~= layer then
        C.JPH_BodyInterface_SetObjectLayer(self.interface, body.raw._joltId, layer)
        body.raw._joltLayer = layer
    end
end

return Filters
