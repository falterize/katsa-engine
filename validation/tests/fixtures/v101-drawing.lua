local ipairs = require('source.engine.math.array').ipairs
return function(UI)
    local function drawLaidOut(ui)
        return ui:drawRaw(true)
    end
    function UI:drawText(n)
        if not n.text then
            return
        end
        local g = katsa.graphics
        if n.textScaled or n.richText then
            local x, y = g.transformPoint(n._x, n._y)
            local x2, y2 = g.transformPoint(n._x + n._width, n._y + n._height)
            local sx, sy, sw, sh = g.getScissor()
            -- These labels already clip every glyph and outline to their rectangle.
            -- Do not prepare text which the active scissor rejects completely.
            if
                x2 <= x
                or y2 <= y
                or sx and (x >= sx + sw or y >= sy + sh or x2 <= sx or y2 <= sy)
            then
                return
            end
            g.push('all')
            g.intersectScissor(x, y, math.max(0, x2 - x), math.max(0, y2 - y))
        end
        require('source.engine.ui.drawing.text').drawLabel(self, n)
        if n.textScaled or n.richText then
            g.pop()
        end
    end
    function UI:drawCanvasGroup(n)
        local g = katsa.graphics
        local alpha = 1 - math.max(0, math.min(1, n.transparency or 0))
        if alpha <= 0 then
            return
        end
        local width, height = math.max(1, math.ceil(n._width)), math.max(1, math.ceil(n._height))
        if
            not n._groupCanvas
            or n._groupCanvas:getWidth() ~= width
            or n._groupCanvas:getHeight() ~= height
            or n._groupDensity ~= self.density
        then
            if n._groupCanvas then
                self.resources:releaseOwned(n._groupCanvas)
            end
            n._groupCanvas =
                self.resources:own(g.newCanvas(width, height, { dpiscale = self.density }))
            n._groupDensity = self.density
            if not n._groupCleanup then
                n._groupCleanup = true
                n:onDestroy(function()
                    if n._groupCanvas then
                        self.resources:releaseOwned(n._groupCanvas)
                        n._groupCanvas = nil
                    end
                end)
            end
        end
        g.push('all')
        g.setCanvas({ n._groupCanvas, stencil = true })
        -- Clear the whole offscreen target, not the inherited viewport scissor.
        g.setScissor()
        g.setStencilTest()
        g.setDepthMode()
        g.clear(0, 0, 0, 0, 0)
        g.setShader()
        g.origin()
        g.translate(-n._x, -n._y)
        local level, stack = self._stencilLevel, self._stencilStack
        self._stencilLevel, self._stencilStack = 0, {}
        n._drawingGroup = true
        self:drawNode(n)
        n._drawingGroup = nil
        self._stencilLevel, self._stencilStack = level, stack
        g.pop()
        -- Temporary Canvas stencil contents can be lost across target switches.
        -- Restore the ancestor masks in the resumed target before compositing.
        if level and level > 0 then
            g.push('all')
            g.setScissor()
            g.setStencilTest()
            g.setShader()
            g.stencil(self._clearStencil, 'replace', 0, false)
            for _, ancestor in ipairs(stack or {}) do
                self._stencilNode = ancestor
                g.stencil(self._stencilRectangle, 'increment', 1, true)
            end
            g.pop()
        end
        g.push('all')
        g.setShader()
        g.setBlendMode('alpha', 'premultiplied')
        g.setColor(alpha, alpha, alpha, alpha)
        g.draw(n._groupCanvas, n._x, n._y)
        g.pop()
    end
    function UI:drawNode(n, x, y)
        if not n:isA('UINode') or not n.visible or n._layoutCollapsed then
            return
        end
        -- A clipped subtree with an empty intersection cannot contribute any pixels.
        -- Unclipped descendants may extend beyond their parent and stay drawable.
        local clip = n.clip and n._childClip
        if clip and (clip[3] <= clip[1] or clip[4] <= clip[2]) then
            return
        end
        if n:isA('CanvasGroup') and (n.transparency or 0) > 0 and not n._drawingGroup then
            self:drawCanvasGroup(n)
            return
        end
        x, y = n._x, n._y
        if n.modifier then
            return
        end
        local clipped = n.clip
        if clipped then
            katsa.graphics.push('all')
            local c = n._childClip
            local x1, y1 = katsa.graphics.transformPoint(c[1], c[2])
            local x2, y2 = katsa.graphics.transformPoint(c[3], c[4])
            katsa.graphics.intersectScissor(x1, y1, math.max(0, x2 - x1), math.max(0, y2 - y1))
        end
        local g = katsa.graphics
        if n._rounded then
            g.push('all')
            self._stencilStack = self._stencilStack or {}
            self._stencilStack[#self._stencilStack + 1] = n
            self._stencilNode = n
            g.stencil(self._stencilRectangle, 'increment', 1, true)
            self._stencilLevel = (self._stencilLevel or 0) + 1
            g.setStencilTest('equal', self._stencilLevel)
        end
        if n.material then
            g.push('all')
            if UI.isWorking(n) or n._materialTime == nil then
                n._materialTime = self.time
            end
            n.material:bind(n._materialTime or self.time)
            g.setShader(n.material.shader)
        end
        n:drawSelf(self)
        for _, child in ipairs(n.children) do
            self:drawNode(child, x, y)
        end
        if n.drawScrollBar then
            n:drawScrollBar(self)
        end
        require('source.engine.ui.drawing.modifiers').drawBorders(n)
        if n:isA('Shader2D') then
            require('source.engine.ui.drawing.compositor').apply(self, n)
        end
        if n.material then
            g.pop()
        end
        if n._rounded then
            self._stencilNode = n
            g.stencil(self._stencilRectangle, 'decrement', 1, true)
            self._stencilLevel = self._stencilLevel - 1
            self._stencilStack[#self._stencilStack] = nil
            g.pop()
        end
        if clipped then
            g.pop()
        end
    end
    function UI:drawRaw(layoutReady)
        if not layoutReady then
            self:layout()
        end
        local g = katsa.graphics
        g.push('all')
        self._stencilLevel, self._stencilStack = 0, {}
        if self.hasCorners then
            g.stencil(self._clearStencil, 'replace', 0, false)
        end
        g.setStencilTest()
        g.translate(self.offsetX, self.offsetY)
        g.scale(self.scale)
        for _, node in ipairs(self.children) do
            self:drawNode(node, 0, 0)
        end
        g.pop()
    end
    function UI:draw()
        assert(
            self.owner or self.parent and self.parent:isA('World3D'),
            'Screen UI must belong to World3D -> World2D'
        )
        self:layout()
        return require('source.engine.ui.drawing.compositor').draw(self, drawLaidOut)
    end
end
