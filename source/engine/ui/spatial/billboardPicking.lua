-- Install one cohesive responsibility on the public class.
local M = require('../../math.math3d')
local Node = require('../../nodes')
local BillboardPicking = {}

function BillboardPicking.install(BillboardUI)
    function BillboardUI:localPoint(x, y)
        local bx, by, t = require('../../surfaces.faces').point(self, self._camera, x, y)
        if not bx then
            return
        end
        local b = self.bounds
        local c = self.resolvedCanvasSize
        return b[1] + bx / c[1] * (b[3] - b[1]), b[2] + by / c[2] * (b[4] - b[2]), t
    end

    function BillboardUI:hit(world, camera, x, y)
        if
            not self.enabled
            or self:getEffectiveOpacity() <= 0
            or not self.drawable
            or not self.interactable
        then
            return
        end
        local bx, by, t = self:localPoint(x, y)
        local b = self.bounds
        if not bx or bx < b[1] or by < b[2] or bx > b[3] or by > b[4] then
            return
        end
        if not self.onTop and world:occluded(camera, x, y, t) then
            return
        end
        return self.ui:hit(bx, by)
    end

    function BillboardUI:getWorldMatrix()
        if self:isA('SurfaceUI') then
            return Node.getClass('Node3D').getWorldMatrix(self)
        end
        local support = require('../../surfaces.support')
        local reference = support.resolve(self)
        local frame = reference and support.frame(self, reference)
        local values = self._spatialValues or {}
        self._spatialValues = values
        local dirty = not self._transformRevision
            or self._supportReference ~= reference
            or self._supportRevision ~= (reference and reference._transformRevision)
            or self._supportInherit ~= self.inheritScale
        for i = 1, 3 do
            if values[i] ~= self.position[i] or values[i + 3] ~= self.rotation[i] then
                dirty = true
            end
            values[i], values[i + 3] = self.position[i], self.rotation[i]
        end
        if dirty then
            self._localTransform =
                M.compose(self.position, self.rotation, { 1, 1, 1 }, self._localTransform)
            self._transform = frame and M.multiply(frame, self._localTransform, self._transform)
                or self._localTransform
            self._transformRevision = (self._transformRevision or 0) + 1
            self._supportReference, self._supportRevision, self._supportInherit =
                reference, reference and reference._transformRevision, self.inheritScale
        end
        return self._transform
    end

    function BillboardUI:setAdornee(reference)
        return require('../../surfaces.support').set(self, reference)
    end
end

return BillboardPicking
