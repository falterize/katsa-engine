local Node = require('../core.baseNode')

local Class = Node.define('SurfaceUI', 'BillboardUI')

function Class.mount(world, properties, parent)
    assert(
        (properties.adornee or parent)
            and (properties.adornee or parent):isA('Node3D')
            and not (properties.adornee or parent):isA('BillboardUI'),
        'SurfaceUI requires a Mesh3D, Attachment3D or Node3D parent'
    )
    if properties.position and #properties.position == 3 then
        properties.spatialPosition = properties.position
        properties.position = nil
    end
    properties.position = properties.position or { 0.5, 0, 0.5, 0 }
    properties.className = 'SurfaceUI'
    properties.parent = parent
    properties.face = properties.face or 'Front'
    require('source.engine.surfaces.faces').validate(properties.face)
    properties.surfaceSize = properties.surfaceSize
    properties.size = properties.size
        or (properties.surfaceSize and { 0, properties.surfaceSize[1], 0, properties.surfaceSize[2] })
        or { 1, 0, 1, 0 }
    properties.surfaceSize = nil
    properties.sizeMode = 'World3D'
    properties.canvasSize = properties.canvasSize or { 512, 256 }
    properties.onTop = properties.onTop == true
    local node = require('source.engine.ui.spatial.billboard').new(world, properties)
    return node
end

function Class:update(world, camera)
    self:resolveCanvas(camera)
    require('source.engine.surfaces.faces').update(self, camera)
end

function Class:localPoint(x, y)
    return require('source.engine.surfaces.faces').point(self, self._camera, x, y)
end

function Class:hit(world, camera, x, y)
    if not self.drawable or not self.enabled or not self.interactable then
        return
    end
    local bx, by, depth = self:localPoint(x, y)
    if
        not bx
        or bx < 0
        or by < 0
        or bx > self.resolvedCanvasSize[1]
        or by > self.resolvedCanvasSize[2]
    then
        return
    end
    if not self.onTop and world:occluded(camera, x, y, depth) then
        return
    end
    return self.ui:hit(bx, by)
end

return Class
