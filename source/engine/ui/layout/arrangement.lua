local ipairs = require('../../math.array').ipairs
local Metrics = require('./metrics')
local Length = require('./scrollLength')
local Canvas = require('./scrollCanvas')
local Display = require('../../core.displayDpi')
local Arrangement = {}

function Arrangement.install(UI)
    local function arrange(list, px, py, pw, ph, clip)
        list = require('source.engine.ui.layout.order').refresh(list)
        for _, n in ipairs(list) do
            if n:isA('Folder') then
                arrange(n.children, px, py, pw, ph, clip)
            elseif n:isA('Node2D') then
                arrange(n.children, 0, 0, n.size[1], n.size[2], nil)
            elseif n:isA('UINode') then
                local x, y, w, h = Metrics.rect(n, pw, ph)
                n._x, n._y, n._width, n._height = px + x, py + y, w, h
                n._clip = clip
                local childClip = clip
                if n.clip then
                    n._childClip = n._childClip or {}
                    local c = n._childClip
                    c[1], c[2], c[3], c[4] = n._x, n._y, n._x + w, n._y + h
                    if clip then
                        c[1] = math.max(c[1], clip[1])
                        c[2] = math.max(c[2], clip[2])
                        c[3] = math.min(c[3], clip[3])
                        c[4] = math.min(c[4], clip[4])
                    end
                    childClip = c
                end
                n._radius = n.radius or 0
                n._rounded = false
                n._backgroundGradient, n._textGradient, n._imageGradient = nil, nil, nil
                for _, child in ipairs(n.children) do
                    if child.applyLayout and UI.isWorking(child) then
                        child:applyLayout(n)
                    end
                end
                local class = rawget(n, '_class')
                local scrollable = rawget(n, 'scrollable')
                if scrollable == nil and class then
                    scrollable = class.scrollable
                end
                if not scrollable then
                    -- Ordinary widgets have no canvas/window state or convergence passes.
                    arrange(
                        n.children,
                        n._x + n:getChildOffsetX(),
                        n._y + n:getChildOffset(),
                        w,
                        h,
                        childClip
                    )
                else
                    if n.clip then
                        local c = n._childClip
                        local frame = n._frameClip or {}
                        n._frameClip = frame
                        frame[1], frame[2], frame[3], frame[4] = c[1], c[2], c[3], c[4]
                    end
                    Length.prepare(n)
                    for pass = 1, 3 do
                        if n.clip then
                            local c = n._childClip
                            c[1], c[2] = n._x + n._windowX, n._y
                            c[3], c[4] = c[1] + n._windowWidth, c[2] + n._windowHeight
                            if clip then
                                c[1], c[2] = math.max(c[1], clip[1]), math.max(c[2], clip[2])
                                c[3], c[4] = math.min(c[3], clip[3]), math.min(c[4], clip[4])
                            end
                        end
                        arrange(
                            n.children,
                            n._x + n:getChildOffsetX(),
                            n._y + n:getChildOffset(),
                            n._windowWidth or w,
                            n._windowHeight or h,
                            childClip
                        )
                        if not Length.update(n) then
                            break
                        end
                    end
                end
            end
        end
    end

    function UI:layout()
        local world = self._sceneWorld or self.owner and self.owner._world
        if world and self._shaderRevision ~= world.shaderLayers.revision then
            self._shaderRevision = world.shaderLayers.revision
            self:invalidate()
        end
        local groupRevision = world and world.layerGroups.revision or 0
        local cameraGroup = self.currentCamera and self.currentCamera.layerGroup or ''
        local materialViewer = world and world._materialCamera
        local viewerGroup = materialViewer and materialViewer.layerGroup or ''
        if
            self._layerRevision ~= groupRevision
            or self._cameraLayer ~= cameraGroup
            or self._hudLayer ~= self.layerGroup
            or self._viewerLayer ~= viewerGroup
        then
            self._layerRevision, self._cameraLayer = groupRevision, cameraGroup
            self._hudLayer, self._viewerLayer = self.layerGroup, viewerGroup
            self:invalidate()
        end
        local revision = self:changed()
        if
            self._layoutRevision == revision
            and self._layoutWidth == self.width
            and self._layoutHeight == self.height
        then
            return
        end
        arrange(self.children, 0, 0, self.width, self.height, nil)
        self._layoutRevision, self._layoutWidth, self._layoutHeight =
            self.revision, self.width, self.height
        self.layoutPasses = (self.layoutPasses or 0) + 1
    end

    function UI:scrollBy(node, deltaY, deltaX)
        self:layout()
        if not node.scrollingEnabled then
            return
        end
        if node.stopMotion then
            node:stopMotion()
            node._exX, node._exY, node._overX, node._overY = 0, 0, 0, 0
        end
        local x, y = Canvas.axes(node)
        deltaX = deltaX or (x and not y and deltaY or 0)
        node.scrollX = node.scrollX + (x and deltaX or 0)
        node.scrollY = node.scrollY + (y and deltaY or 0)
        if Canvas.clamp(node) or deltaX ~= 0 or deltaY ~= 0 then
            self:invalidate()
        end
    end

    function UI:wheel(x, y, deltaY, deltaX)
        local node = self:hit(x, y)
        while node and node ~= self do
            if node.scrollable and node.scrollingEnabled then
                local horizontal, vertical = Canvas.axes(node)
                local dx = deltaX or 0
                if horizontal and (not vertical or katsa.keyboard.isDown('lshift', 'rshift')) then
                    dx, deltaY = dx + deltaY, 0
                end
                self:scrollBy(node, -deltaY * 48, -dx * 48)
                return true
            end
            node = node.parent
        end
    end

    function UI:setDensity(density)
        -- Rasterize at the actual target density (including 125%/175% DPI).
        -- Rounding up to half steps resampled every glyph at fractional DPI.
        density = math.max(0.25, math.min(4, density))
        if density ~= self.density then
            self.density = density
            self:invalidate()
        end
    end

    function UI:fit(width, height)
        local x, y, w, h = katsa.window.getSafeArea()
        if not w or w <= 0 or h <= 0 then
            x, y, w, h = 0, 0, width, height
        end
        if self.layoutMode == 'Viewport' then
            local scale = Display.uiScale()
            self.width, self.height = w / scale, h / scale
            if self.content ~= self.owner then
                self.content.size = { 1, 0, 1, 0 }
            end
            self.scale, self.offsetX, self.offsetY = scale, x, y
            self:setDensity(scale * katsa.graphics.getDPIScale())
            return
        end
        self.scale = math.min(w / self.width, h / self.height)
        self.offsetX = math.floor(x + (w - self.width * self.scale) / 2 + 0.5)
        self.offsetY = math.floor(y + (h - self.height * self.scale) / 2 + 0.5)
        self:setDensity(self.scale * katsa.graphics.getDPIScale())
    end
    -- Convert an authored reference layout once; offsets retain their pixel meaning thereafter.
    -- Scrolled rows keep their vertical pixel positions, while columns follow their parent.
    function UI:adaptReference(width, height)
        self.width, self.height = width, height
        self:layout()

        local function visit(list, pw, ph, scrolled, preserve)
            for _, node in ipairs(list) do
                if node:isA('UINode') then
                    local w, h = node._width, node._height
                    local keep = preserve or node._viewportAuthored
                    if not node.modifier and not keep then
                        local pos, size = node.position, node.size
                        if pos and not node.positionRelativeTo and not node.relativeTo then
                            node.position = {
                                pos[1] + pos[2] / math.max(1, pw),
                                0,
                                scrolled and pos[3] or pos[3] + pos[4] / math.max(1, ph),
                                scrolled and pos[4] or 0,
                            }
                        end
                        if size and not node.sizeRelativeTo and not node.relativeTo then
                            node.size = {
                                size[1] + size[2] / math.max(1, pw),
                                0,
                                scrolled and size[3] or size[3] + size[4] / math.max(1, ph),
                                scrolled and size[4] or 0,
                            }
                        end
                        if node.text and node.textScaled == nil then
                            node.textScaled = true
                            node.maxTextSize = node.fontSize or 22
                            node.minTextSize = 8
                        end
                    end
                    visit(node.children, w, h, node.scrollable, keep)
                end
            end
        end
        visit(self.children, width, height, false)
        self.layoutMode = 'Viewport'
        self:invalidate()
    end
end

return Arrangement
