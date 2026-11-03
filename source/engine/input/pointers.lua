local ipairs = require('../math.array').ipairs
local pairs = require('../math.array').pairs
-- Install one cohesive responsibility on the public class.
local Capture = require('./uiCapture')
local Routing = require('./pointerRouting')
local hasWorldCamera, visualPanelAt = Routing.hasWorldCamera, Routing.visualPanelAt
local Pointers = {}

function Pointers.install(Input)
    function Input:press(id, x, y)
        self:flushHover()
        local scene = self.scene
        if self.captures[id] then
            self:cancel(id)
        end
        local node = scene.ui and scene.ui:hit(x, y)
        local focused = require('source.engine.ui.widgets.textFocus').current
        if focused and focused ~= node then
            focused:blur()
        end
        if node then
            for _, capture in pairs(self.captures) do
                if capture.node == node and not node:isA('ViewportFrame') then
                    return
                end
            end
            self.captures[id] = Capture.new(node, x, y)
            Capture.press(self.captures[id], x, y, id)
            return
        end
        -- The joystick owns its region before any world UI panel behind it.
        if self.layout then
            local ui, j = scene.ui, self.layout.joystick
            local lx, ly = (x - ui.offsetX) / ui.scale, (y - ui.offsetY) / ui.scale
            if not j.blocked and (lx - j.x) ^ 2 + (ly - j.y) ^ 2 <= j.radius ^ 2 then
                if not self.joystickId then
                    self.joystickId = id
                    self.captures[id] = { kind = 'joystick' }
                    self:move(id, x, y, 0, 0)
                end
                return
            end
        end
        local worldUICovered = false
        if hasWorldCamera(scene) and scene.renderer then
            local list = scene.renderer.top
            for pass = 1, 2 do
                if pass == 2 then
                    list = scene.renderer.transparent
                end
                for i = #list, 1, -1 do
                    local b = list[i]
                    if b.canvas then
                        worldUICovered = worldUICovered or visualPanelAt(scene, b, x, y)
                        local hit = b:hit(scene.world, scene.camera, x, y)
                        if hit then
                            for _, capture in pairs(self.captures) do
                                if capture.node == hit then
                                    return
                                end
                            end
                            local bx, by = b:localPoint(x, y)
                            self.captures[id] = Capture.new(hit, bx, by, b, x, y)
                            Capture.press(self.captures[id], bx, by, id)
                            return
                        end
                    end
                end
            end
        end
        local covered = worldUICovered or scene.ui and scene.ui:blocksWorldClick(x, y)
        local detector = not covered
            and hasWorldCamera(scene)
            and require('source.engine.world.picking').detector(scene.world, scene.camera, x, y)
        local pending = detector and { detector = detector, startX = x, startY = y, moved = false }
        if not self.layout or not hasWorldCamera(scene) then
            if pending then
                self.captures[id] = { kind = 'click', pendingClick = pending }
            end
            return
        end
        local s = scene.ui.scale
        local lx = (x - scene.ui.offsetX) / s
        local ly = (y - scene.ui.offsetY) / s
        local j = self.layout.joystick
        if (lx - j.x) ^ 2 + (ly - j.y) ^ 2 <= j.radius ^ 2 then
            if not self.joystickId then
                self.joystickId = id
                self.captures[id] = { kind = 'joystick' }
                self:move(id, x, y, 0, 0)
            end
            return
        end
        local c = self.layout.camera
        if
            lx >= c.x
            and ly >= c.y
            and lx < c.x + c.width
            and ly < c.y + c.height
            and not self.cameraId
        then
            self.cameraId = id
            self.captures[id] = { kind = 'camera', pendingClick = pending }
        elseif pending and not self.cameraId then
            self.captures[id] = { kind = 'click', pendingClick = pending }
        end
    end

    function Input:move(id, x, y, dx, dy)
        local c = self.captures[id]
        if not c then
            if id == 'mouse' then
                -- Hit-testing the UI costs 0.2-0.5 ms; a fast mouse delivers several moves per
                -- frame, so only the newest position is resolved (see flushHover).
                self.hoverX, self.hoverY = x, y
            end
            return
        end
        if
            c.pendingClick
            and (
                (x - c.pendingClick.startX) ^ 2 + (y - c.pendingClick.startY) ^ 2 > 64
                or math.abs(dx) + math.abs(dy) > 8
            )
        then
            c.pendingClick.moved = true
        end
        if c.node then
            c.lastX, c.lastY = x, y
            local nx, ny = Capture.point(c, x, y)
            if not nx then
                return
            end
            Capture.move(c, nx, ny, id)
            return
        end
        if c.kind == 'joystick' then
            local ui, j = self.scene.ui, self.layout.joystick
            local ax = ((x - ui.offsetX) / ui.scale - j.x) / j.radius
            local ay = (j.y - (y - ui.offsetY) / ui.scale) / j.radius
            local n = math.sqrt(ax * ax + ay * ay)
            self.axisX, self.axisY = ax / math.max(1, n), ay / math.max(1, n)
            if n < 0.08 then
                self.axisX, self.axisY = 0, 0
            end
        elseif c.kind == 'camera' then
            self.actions:look(dx / self.scene.ui.scale, dy / self.scene.ui.scale)
        end
    end

    function Input:release(id, x, y)
        local c = self.captures[id]
        if not c then
            return
        end
        local pending = c.pendingClick
        if
            pending
            and not pending.moved
            and x
            and y
            and (x - pending.startX) ^ 2 + (y - pending.startY) ^ 2 <= 64
        then
            local scene = self.scene
            local blocked = scene.ui and (scene.ui:hit(x, y) or scene.ui:blocksWorldClick(x, y))
            for _, list in ipairs({
                scene.renderer and scene.renderer.top or {},
                scene.renderer and scene.renderer.transparent or {},
            }) do
                for _, board in ipairs(list) do
                    if visualPanelAt(scene, board, x, y) then
                        blocked = true
                    end
                end
            end
            if
                not blocked
                and hasWorldCamera(scene)
                and require('source.engine.world.picking').detector(
                        scene.world,
                        scene.camera,
                        x,
                        y
                    )
                    == pending.detector
            then
                pending.detector:activate(id)
            end
        end
        if c.kind == 'joystick' then
            self.axisX, self.axisY = 0, 0
            self.joystickId = nil
        end
        if c.kind == 'camera' then
            self.cameraId = nil
        end
        if c.node then
            local nx, ny = Capture.point(c, x or c.lastX or 0, y or c.lastY or 0)
            if nx then
                Capture.release(c, nx, ny, id)
            else
                c.node.ui:pointer(c.node, 'cancel', 0, 0, id)
            end
        end
        self.captures[id] = nil
    end

    -- Resolves the hover for the latest mouse position seen since the last flush. Called once per
    -- frame from Input:update and before presses, so enter/leave/hover events keep their order.
    function Input:flushHover()
        local x, y = self.hoverX, self.hoverY
        if x then
            self.hoverX, self.hoverY = nil, nil
            self:hover(x, y)
        end
    end

    function Input:hover(x, y)
        local scene = self.scene
        local node = scene.ui and scene.ui:hit(x, y)
        local nx, ny = x, y
        if not node and hasWorldCamera(scene) and scene.renderer then
            for _, list in ipairs({ scene.renderer.top, scene.renderer.transparent }) do
                for i = #list, 1, -1 do
                    local board = list[i]
                    if board.canvas then
                        local hit = board:hit(scene.world, scene.camera, x, y)
                        if hit then
                            node = hit
                            nx, ny = board:localPoint(x, y)
                            break
                        end
                    end
                end
                if node then
                    break
                end
            end
        end
        if self.hovered ~= node then
            if self.hovered and not self.hovered.destroyed then
                local ox, oy = x, y
                local owner = self.hovered.ui.owner
                if owner and owner.localPoint then
                    ox, oy = owner:localPoint(x, y)
                    ox, oy = ox or 0, oy or 0
                end
                self.hovered.ui:pointer(self.hovered, 'leave', ox, oy, 'mouse')
            end
            self.hovered = node
            if node then
                node.ui:pointer(node, 'enter', nx, ny, 'mouse')
            end
        end
        if node then
            node.ui:pointer(node, 'hover', nx, ny, 'mouse')
        end
    end
end

return Pointers
