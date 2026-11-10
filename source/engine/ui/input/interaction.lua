local Interaction = {}

local function layerVisible(node)
    return not node.ui or node.ui:layerVisible(node)
end

function Interaction.install(UI)
    function UI.contains(node, x, y)
        local left, top, width, height = node._x, node._y, node._width, node._height
        if x < left or y < top or x > left + width or y > top + height then
            return false
        end
        if not node._rounded then
            return true
        end
        local radius = node._radius
        local cx = math.max(left + radius, math.min(left + width - radius, x))
        local cy = math.max(top + radius, math.min(top + height - radius, y))
        return (x - cx) ^ 2 + (y - cy) ^ 2 <= radius ^ 2
    end

    local function hit(list, x, y, px, py)
        list = require('source.engine.ui.layout.order').get(list)
        for i = #list, 1, -1 do
            local n = list[i]
            if
                n:isA('UINode')
                and n.visible
                and layerVisible(n)
                and not n._layoutCollapsed
                and n.enabled
                and n.interactable ~= false
                and (not n:isA('CanvasGroup') or (n.transparency or 0) < 1)
            then
                local nx, ny = n._x, n._y
                local clip = n._clip
                local inClip = not clip
                    or (x >= clip[1] and y >= clip[2] and x <= clip[3] and y <= clip[4])
                if n._rounded then
                    inClip = inClip and UI.contains(n, x, y)
                end
                -- Bars render above their children, including content with no inset.
                if inClip and n.scrollBarAt and n:scrollBarAt(x, y) and UI.contains(n, x, y) then
                    return n
                end
                local found = inClip and hit(n.children, x, y, nx, ny)
                if found then
                    return found
                end
                if
                    inClip
                    and (n.interactive or n.onPress or n.capture)
                    and UI.contains(n, x, y)
                then
                    return n
                end
            end
        end
    end
    -- Conservative visual UI rectangles block 3D taps even when disabled/decorative.
    -- With `onlyInteractable`, branches whose Interactable is off are ignored (they take no input).
    function UI:blocksWorldClick(x, y, onlyInteractable)
        if self.visible == false or (self.transparency or 0) >= 1 then
            return false
        end
        self:layout()
        x, y = (x - self.offsetX) / self.scale, (y - self.offsetY) / self.scale
        local screenX, screenY = x * self.scale + self.offsetX, y * self.scale + self.offsetY
        local Style = require('source.engine.ui.style')

        local function visit(list, x, y)
            for i = #list, 1, -1 do
                local n = list[i]
                if
                    n:isA('UINode')
                    and n.visible
                    and layerVisible(n)
                    and not n._layoutCollapsed
                    and not n.modifier
                    and (not onlyInteractable or n.interactable ~= false and n.enabled ~= false)
                    and (not n:isA('CanvasGroup') or (n.transparency or 0) < 1)
                then
                    local clip = n._clip
                    local inside = not clip
                        or x >= clip[1] and y >= clip[2] and x <= clip[3] and y <= clip[4]
                    if n._rounded then
                        inside = inside and UI.contains(n, x, y)
                    end
                    if inside then
                        if visit(n.children, x, y) then
                            return true
                        end
                        if UI.contains(n, x, y) then
                            local background = Style.color(n, 'background')
                            if
                                background and Style.alpha(n, 'background', background) > 0
                                or n.image and Style.alpha(n, 'image', Style.color(n, 'image')) > 0
                                or n.text
                                    and n.text ~= ''
                                    and Style.alpha(n, 'text', Style.color(n, 'text')) > 0
                            then
                                return true
                            end
                        end
                    end
                end
            end
            return false
        end
        return visit(self.children, x, y)
            or require('source.engine.ui.spatial.plane').hit(
                self,
                self.children,
                screenX,
                screenY,
                visit,
                true
            )
            or false
    end

    function UI:hit(x, y)
        self:layout()
        if (self.transparency or 0) >= 1 or self.visible == false then
            return
        end
        return hit(
            self.children,
            (x - self.offsetX) / self.scale,
            (y - self.offsetY) / self.scale,
            0,
            0
        ) or require('source.engine.ui.spatial.plane').hit(self, self.children, x, y, hit)
    end

    function UI:position(node)
        self:layout()
        return node._x, node._y
    end

    function UI:pointer(node, phase, x, y, id)
        self:layout()
        if phase ~= 'cancel' then
            local ancestor = node
            while ancestor do
                if
                    ancestor.destroyed
                    or ancestor:isA('UINode') and not layerVisible(ancestor)
                    or ancestor.visible == false
                    or ancestor.enabled == false
                    or ancestor.interactable == false
                    or (
                        (
                            ancestor:isA('CanvasGroup')
                            or ancestor:isA('World2D')
                            or ancestor:isA('Node2D')
                        ) and (ancestor.transparency or 0) >= 1
                    )
                then
                    phase = 'cancel'
                    break
                end
                ancestor = ancestor.parent
            end
        end
        local owner = require('source.engine.ui.spatial.plane').owner(node)
        local px, py = x, y
        if owner then
            px, py = require('source.engine.ui.spatial.plane').localPoint(self, owner, x, y)
            px, py = px * self.scale + self.offsetX, py * self.scale + self.offsetY
        end
        node:pointer(self, phase, px, py, id)
        node:emit(phase, node, x, y, id)
        if phase == 'release' then
            -- A release over the node that was pressed is a click.
            local lx, ly = (px - self.offsetX) / self.scale, (py - self.offsetY) / self.scale
            if lx >= node._x and lx < node._x + node._width
                and ly >= node._y and ly < node._y + node._height
            then
                node:emit('click', node, x, y, id)
            end
        end
        local handler = phase == 'enter' and node.onEnter
            or phase == 'leave' and node.onLeave
            or phase == 'hover' and node.onHover
            or phase == 'press' and node.onPress
            or phase == 'move' and node.onMove
            or phase == 'release' and node.onRelease
            or phase == 'cancel' and node.onCancel
        if handler then
            handler(node, x, y, id)
        end
    end
end

return Interaction
