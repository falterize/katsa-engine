local Node = require('../core.baseNode')
local Math = require('../../math.math3d')

local Class = Node.define('Decal3D', 'Node3D')
require('../../components.image').describe(Class)
Class.propertySchema.mode = {
    visibleWhen = function()
        return false
    end,
}

function Class.mount(world, properties, parent)
    properties.face = properties.face or 'Front'
    require('source.engine.surfaces.faces').validate(properties.face)
    properties._legacyTileFit = properties.imageMode == nil
        and properties.mode == 'Tiles'
        and properties.fitMode ~= nil
        and properties.fitMode ~= 'Tile'
    properties.mode = properties.imageMode or properties.mode or 'Decal'
    properties.imageMode = properties.mode
    properties.transparency = properties.transparency or 0
    properties.color = properties.color or { 1, 1, 1 }
    properties.onTop = properties.onTop == true
    properties.unlit = properties.unlit ~= false
    properties.maxDistance = properties.maxDistance or 500
    properties.zIndex = properties.zIndex or 0
    properties.atlasGrid = properties.atlasGrid or { 1, 1 }
    properties.atlasFrame = properties.atlasFrame or 0
    properties.textureSize = properties.textureSize or { 8, 8 }
    properties.textureOffset = properties.textureOffset or { 0, 0 }
    properties.tileSize = properties.tileSize or { 0.25, 0, 0.25, 0 }
    properties.tileOffset = properties.tileOffset or { 0, 0 }
    properties.fitMode = properties.fitMode or 'Tile'
    properties.canvasPixelsPerUnit = properties.canvasPixelsPerUnit or 16
    properties.imageOffset = properties.imageOffset or { 0, 0 }
    properties.imageRotation = properties.imageRotation or 0
    if properties.position and #properties.position == 3 then
        properties.spatialPosition = properties.position
        properties.position = nil
    end
    properties.anchorPoint = properties.anchorPoint or { 0.5, 0.5 }
    properties.relativeTo = properties.relativeTo or 'XY'
    properties.spatialPosition = properties.spatialPosition or { 0, 0, 0 }
    properties.position = properties.position or { 0.5, 0, 0.5, 0 }
    assert(
        not properties.size or #properties.size == 4,
        'Decal3D Size requires four components; use surfaceSize only for legacy loading'
    )
    properties.size = properties.size
        or (properties.surfaceSize and { 0, properties.surfaceSize[1], 0, properties.surfaceSize[2] })
        or { 1, 0, 1, 0 }
    properties.surfaceSize = nil
    require('source.engine.components.image').initialize(properties)
    properties._decalMode = properties.imageMode
    properties._world = world
    properties.matrix = Math.identity()
    properties.normal = {}
    properties.geometry = world.surfaceQuad
    properties.image = properties.image or ''
    properties.textureImage = require('source.engine.components.image').resolve(
        world.resources,
        properties,
        properties.image,
        world.environment
    )
    local reference = properties.adornee
    if reference then
        local ok, reason =
            require('source.engine.surfaces.support').valid({ _world = world }, reference)
        assert(ok, reason)
    end
    rawset(properties, 'adornee', nil)
    properties.brightness = properties.brightness or 1
    properties.supportSize = properties.supportSize or { 1, 1, 1 }
    require('source.engine.core.validate').vector(properties.supportSize, 'Decal3D.supportSize', 3)
    for i = 1, 3 do
        assert(properties.supportSize[i] > 0, 'Decal3D.supportSize must be positive')
    end
    assert(
        type(properties.brightness) == 'number'
            and properties.brightness >= 0
            and properties.brightness < math.huge,
        'Decal3D.brightness must be finite and nonnegative'
    )
    local node = Node.adopt(properties, 'Decal3D')
    require('source.engine.surfaces.support').initialize(node, reference)
    node.parent = parent
    world.decals[#world.decals + 1] = node
    node:onDestroy(function()
        for i = #world.decals, 1, -1 do
            if world.decals[i] == node then
                table.remove(world.decals, i)
                break
            end
        end
    end)
    return node
end

function Class:update(world, camera)
    if self.mode ~= self._decalMode and self.imageMode == self._decalMode then
        self.imageMode = self.mode
    end
    self.mode = self.imageMode
    if
        self.image ~= self._imagePath
        or self.xml ~= self._xmlPath
        or self.imageMode ~= self._decalMode
        or require('source.engine.components.image').pixelate(self, world.environment)
            ~= self._imagePixel
    then
        self.textureImage = require('source.engine.components.image').resolve(
            world.resources,
            self,
            self.image,
            world.environment
        )
        self._xmlPath, self._decalMode = self.xml, self.imageMode
        self._imagePath, self._imagePixel =
            self.image, require('source.engine.components.image').pixelate(self, world.environment)
    end
    assert(
        self.mode == 'Decal'
            or self.mode == 'Texture'
            or self.mode == 'Tiles'
            or self.mode == 'Atlas'
            or self.mode == 'XML',
        'Decal3D.mode must be Decal, Texture, Tiles or Atlas'
    )
    require('source.engine.surfaces.faces').update(self, camera)
end

function Class:setAdornee(reference)
    return require('source.engine.surfaces.support').set(self, reference)
end

return Class
