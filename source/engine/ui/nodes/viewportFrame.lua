local Capture = require('../../input.uiCapture')
local ipairs = require('../../math.array').ipairs
local Node = require('../../nodes')
local PixelGrid = require('../drawing.pixelGrid')

local Class = Node.define('ViewportFrame', 'Frame')
Class.interactive = true
Class.propertySchema = {
    pixelate = {
        get = function(node)
            return require('../../components.image').pixelate(
                node,
                node._sceneWorld.environment
            )
        end,
    },
}

function Class.initialize(self)
    self.clip = self.clip ~= false
    local scale = self.renderScale or 1
    self.canvasSize = self.canvasSize or { scale, 0, scale, 0 }
    self.renderScale = nil
    self.autoUpdate = self.autoUpdate ~= false
end

function Class:getWorld()
    for _, node in ipairs(self.children) do
        if node:isA('World3D') and not node.destroyed then
            return node._world
        end
    end
end

function Class:updateContents(dt)
    local world = self:getWorld()
    if world and self.autoUpdate then
        world.root:update(dt)
    end
end

function Class:drawSelf(ui)
    Class.base.drawSelf(self, ui)
    local world = self:getWorld()
    if not world or self._width <= 0 or self._height <= 0 then
        return
    end
    local w, h = require('../layout.metrics').resolve(
        self.canvasSize,
        self._width,
        self._height
    )
    assert(w > 0 and h > 0, 'ViewportFrame.CanvasSize must resolve to positive dimensions')
    local limits = katsa.graphics.getSystemLimits()
    local budget = world.environment.render.maxRenderPixels
    local ratio = math.min(1, limits.texturesize / math.max(w, h), math.sqrt(budget / (w * h)))
    w, h = math.max(1, math.floor(w * ratio)), math.max(1, math.floor(h * ratio))
    self._canvasWidth, self._canvasHeight = w, h
    local filter = require('../../components.image').pixelate(self, world.environment)
            and 'nearest'
        or 'linear'
    local canvas
    if world.activeCamera then
        if not world.renderer then
            world.renderer =
                require('../../graphics.pipeline.renderer').new(world.resources)
        end
        world.renderer.targetWidth, world.renderer.targetHeight = w, h
        canvas = world.renderer:draw(world, world.activeCamera, world.viewportTime or 0, true)
    end
    local g = katsa.graphics
    -- UI density follows the displayed frame independently of the 3D render resolution.
    local density = math.max(
        0.25,
        math.min(
            4,
            ui.density * math.max(self._width / w, self._height / h),
            limits.texturesize / math.max(w, h),
            math.sqrt(budget / (w * h))
        )
    )
    local pixelWidth, pixelHeight =
        math.max(1, math.ceil(w * density)), math.max(1, math.ceil(h * density))
    if
        not world.overlayCanvas
        or world.overlayCanvas:getWidth() ~= pixelWidth
        or world.overlayCanvas:getHeight() ~= pixelHeight
    then
        if world.overlayCanvas then
            world.resources:releaseOwned(world.overlayCanvas)
        end
        world.overlayCanvas =
            world.resources:own(g.newCanvas(pixelWidth, pixelHeight, { dpiscale = 1 }))
    end
    self._overlayDensity = density
    world.overlayCanvas:setFilter(filter, filter)
    if canvas then
        canvas:setFilter(filter, filter)
    end
    g.push('all')
    g.setCanvas({ world.overlayCanvas, stencil = true })
    g.origin()
    g.setScissor()
    g.setStencilTest()
    g.setShader()
    g.setDepthMode()
    g.setMeshCullMode('none')
    g.setBlendMode('alpha', 'alphamultiply')
    g.clear(0, 0, 0, 0, 0)
    for _, inner in ipairs(world.uis) do
        inner.width, inner.height, inner.scale, inner.offsetX, inner.offsetY = w, h, density, 0, 0
        inner:setDensity(density)
        inner:draw()
    end
    g.flushBatch()
    g.pop()
    -- Canvas switches can retain a driver scissor converted for the old target.
    require('../../graphics.state').reapplyScissor()
    require('../../graphics.state').restoreUIStencil(ui)
    g.push('all')
    g.setShader()
    g.setStencilTest()
    g.setDepthMode()
    g.setMeshCullMode('none')
    g.setColor(1, 1, 1, 1)
    g.setBlendMode('alpha', 'premultiplied')
    local sx, sy = self._width / w, self._height / h
    if canvas then
        g.draw(canvas, self._x, self._y, 0, sx, sy)
    end
    local x, y = PixelGrid.snap(g, self._x, self._y)
    g.draw(world.overlayCanvas, x, y, 0, sx / density, sy / density)
    g.flushBatch()
    g.pop()
end

function Class:pointer(ui, phase, x, y, id)
    local world = self:getWorld()
    if not world or not self._canvasWidth then
        self._captures = {}
        return
    end
    local lx = ((x - ui.offsetX) / ui.scale - self._x)
        * self._canvasWidth
        / math.max(1, self._width)
    local ly = ((y - ui.offsetY) / ui.scale - self._y)
        * self._canvasHeight
        / math.max(1, self._height)
    self._captures = self._captures or {}
    if phase == 'press' then
        for i = #world.uis, 1, -1 do
            local inner = world.uis[i]
            local hit = inner:hit(lx * inner.scale, ly * inner.scale)
            if hit then
                local capture = Capture.new(hit, lx * inner.scale, ly * inner.scale)
                capture.ui = inner
                self._captures[id] = capture
                Capture.press(capture, lx * inner.scale, ly * inner.scale, id)
                return
            end
        end
        self._captures[id] = {
            click = world.activeCamera and require('../../world.picking').detector(
                world,
                world.activeCamera,
                lx,
                ly
            ),
            x = lx,
            y = ly,
        }
    else
        local capture = self._captures[id]
        if not capture then
            return
        end
        if capture.node then
            local px, py = lx * capture.ui.scale, ly * capture.ui.scale
            if phase == 'move' then
                Capture.move(capture, px, py, id)
            elseif phase == 'release' then
                Capture.release(capture, px, py, id)
            else
                capture.ui:pointer(capture.node, phase, px, py, id)
            end
        elseif
            phase == 'release'
            and capture.click
            and (lx - capture.x) ^ 2 + (ly - capture.y) ^ 2 < 64
        then
            if
                world.activeCamera
                and require('../../world.picking').detector(
                        world,
                        world.activeCamera,
                        lx,
                        ly
                    )
                    == capture.click
            then
                capture.click:activate(id)
            end
        end
        if phase == 'release' or phase == 'cancel' then
            self._captures[id] = nil
        end
    end
end

return Class
