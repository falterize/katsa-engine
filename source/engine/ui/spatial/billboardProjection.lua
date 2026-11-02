local ipairs = require('../../math.array').ipairs
-- Install one cohesive responsibility on the public class.
local M = require('../../math.math3d')
local Validate = require('../../core.validate')
local BillboardProjection = {}

function BillboardProjection.install(BillboardUI)
    function BillboardUI:update(world, camera)
        assert(self.scale == nil, 'World3D UI uses Size rather than scale')
        for _, key in ipairs({
            'position',
            'offset',
            'offsetWorldSpace',
            'extentsOffset',
            'extentsOffsetWorldSpace',
        }) do
            Validate.vector(self[key], 'BillboardUI.' .. key, 3)
        end
        local support = require('source.engine.surfaces.support')
        local reference = support.resolve(self)
        if not reference then
            self.drawable = false
            return
        end
        Validate.vector(self.rotation, 'BillboardUI.rotation', 3)
        self:resolveCanvas(camera)
        local frame = support.frame(self, reference, true)
        local x, y, z = M.transform(
            frame,
            self.position[1] + self.offset[1],
            self.position[2] + self.offset[2],
            self.position[3] + self.offset[3]
        )
        self.anchorWorldPosition = self.anchorWorldPosition or {}
        local anchor = self.anchorWorldPosition
        anchor[1], anchor[2], anchor[3] =
            x + self.offsetWorldSpace[1], y + self.offsetWorldSpace[2], z + self.offsetWorldSpace[3]
        local p = self.worldPosition
        -- Camera3D/world aligned bounding-box half extents, as in Roblox BillboardGui.
        local view, global = support.halfExtents(self, reference, camera)
        for i = 1, 3 do
            p[i] = anchor[i] + self.extentsOffsetWorldSpace[i] * global[i]
            for j, basis in ipairs({ camera.right, camera.up, camera.forward }) do
                p[i] = p[i] + basis[i] * self.extentsOffset[j] * view[j]
            end
        end
        self.screenX, self.screenY, self.depth = camera:project(p)
        self.drawable = self:isVisible()
            and (#self.size == 4 or (self.size[1] > 0 and self.size[2] > 0))
            and self:getEffectiveOpacity() > 0
            and self.depth ~= nil
            and (
                self.maxDistance <= 0
                or M.distanceSquared(p, camera.worldPosition or camera.position)
                    <= self.maxDistance ^ 2
            )
        if not self.drawable then
            return
        end
        local w, h = self:resolvedSize(camera)
        assert(
            self.sizeMode == 'Screen' or self.sizeMode == 'World3D',
            'BillboardUI sizeMode must be Screen or World3D'
        )
        assert(w >= 0 and h >= 0, 'BillboardUI size must resolve non-negative dimensions')
        if w == 0 or h == 0 then
            self.drawable = false
            return
        end
        -- World units per screen pixel at this depth (constant for orthographic cameras).
        local pixels = camera:pixelsPerUnitAt(self.depth)
        local unitsPerPixel = 1 / pixels
        if self.sizeMode == 'Screen' then
            local scale = #self.size == 4 and 1 or camera.height / camera.referenceHeight
            w = w * scale * unitsPerPixel
            h = h * scale * unitsPerPixel
        end
        if self.minScreenSize then
            w = math.max(w, self.minScreenSize[1] * unitsPerPixel)
            h = math.max(h, self.minScreenSize[2] * unitsPerPixel)
        end
        self.screenWidth, self.screenHeight = w * pixels, h * pixels
        local bounds = self.bounds
        local anchor = self.anchorPoint or { 0.5, 0.5 }
        local offsetX = ((bounds[1] + bounds[3]) / 2 - self.resolvedCanvasSize[1] * anchor[1])
            * w
            / self.resolvedCanvasSize[1]
        local offsetY = -((bounds[2] + bounds[4]) / 2 - self.resolvedCanvasSize[2] * anchor[2])
            * h
            / self.resolvedCanvasSize[2]
        w = w * (bounds[3] - bounds[1]) / self.resolvedCanvasSize[1]
        h = h * (bounds[4] - bounds[2]) / self.resolvedCanvasSize[2]
        if self.screenPosition then
            local sx, sy = require('source.engine.ui.layout.metrics').resolve(
                self.screenPosition,
                camera.width,
                camera.height,
                self.positionRelativeTo or self.relativeTo
            )
            self.screenX, self.screenY = self.screenX + sx, self.screenY + sy
            offsetX = offsetX + sx * unitsPerPixel
            offsetY = offsetY - sy * unitsPerPixel
        end
        local m = self.matrix
        local base = self._facingFrame or M.identity()
        self._facingFrame = base
        for i = 1, 3 do
            base[(i - 1) * 4 + 1] = camera.right[i]
            base[(i - 1) * 4 + 2] = camera.up[i]
            base[(i - 1) * 4 + 3] = camera.forward[i]
            base[(i - 1) * 4 + 4] = p[i]
        end
        self._panelRotation = M.compose(
            { 0, 0, 0 },
            self.rotation,
            { 1, 1, 1 },
            self._panelRotation
        )
        M.multiply(base, self._panelRotation, m)
        for i = 1, 3 do
            local row = (i - 1) * 4
            m[row + 4] = m[row + 4] + m[row + 1] * offsetX + m[row + 2] * offsetY
            m[row + 1] = m[row + 1] * w
            m[row + 2] = m[row + 2] * h
        end
        M.normalMatrix(m, self.normal)
        self._surfaceInverse = require('source.engine.math.affine').inverse(m, self._surfaceInverse)
    end
end

return BillboardProjection
