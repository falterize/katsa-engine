local ipairs = require('../math.array').ipairs
local pairs = require('../math.array').pairs
-- Install one cohesive responsibility on the public class.
local Capture = require('./uiCapture')
local Routing = require('./pointerRouting')
local hasWorldCamera, visualPanelAt = Routing.hasWorldCamera, Routing.visualPanelAt
local Movement = {}

function Movement.install(Input)
    function Input:update(dt)
        for id, c in pairs(self.captures) do
            if
                c.node
                and (
                    not require('../ui').canInteract(c.node)
                    or c.billboard and not c.billboard.drawable
                )
            then
                if
                    c.scroll
                    and (not c.billboard or c.billboard.drawable)
                    and require('../ui').canInteract(c.scroll)
                then
                    c.node.ui:pointer(c.node, 'cancel', 0, 0, id)
                    c.node = c.scroll
                    c.pendingPress = false
                    local x, y = Capture.point(c, c.lastX, c.lastY)
                    c.node.ui:pointer(c.node, 'press', x or 0, y or 0, id)
                else
                    c.node.ui:pointer(c.node, 'cancel', 0, 0, id)
                    self.captures[id] = nil
                end
            end
        end
        local focused = require('../ui.widgets.textFocus').current
        if focused and not require('../ui').canInteract(focused) then
            focused:blur()
            focused = nil
        end
        if focused and not self._typing then
            self.actions:reset()
        end
        self._typing = focused ~= nil
        if focused or self.scene.workspace and self.scene.workspace.editing then
            if self.scene.character then
                self.scene.character:setMove(0, 0)
            end
            return
        end
        if not self.layout then
            return
        end
        if self.scene.freeDebugCamera and self.scene.character then
            self.scene.character:setMove(0, 0)
        end
        local movement = self.actions:updateMove(self.axisX, self.axisY, self.up, self.down)
        local x, z = movement[1], movement[3]
        local look = self.actions.values.Look
        if hasWorldCamera(self.scene) and (look[1] ~= 0 or look[2] ~= 0) then
            if self.actions.listeners.Look then
                self.actions.listeners.Look(self.scene, look, dt)
            else
                local rig = self.scene.camera._controller
                if rig and self.scene.camera.followMode ~= 'Free' then
                    rig:look(look[1], look[2])
                else
                    self.scene.camera:look(look[1], look[2], self.layout.sensitivity)
                end
            end
        end
        for name in pairs(self.actions.pressed) do
            if self.actions:consume(name) then
                if self.actions.listeners[name] then
                    self.actions.listeners[name](self.scene, name)
                elseif
                    name == 'Jump'
                    and self.scene.character
                    and not self.scene.freeDebugCamera
                then
                    self.scene.character:jump()
                elseif
                    name == 'Interact'
                    and hasWorldCamera(self.scene)
                    and not (self.scene.workspace and self.scene.workspace.opened)
                then
                    local scene = self.scene
                    local camera = scene.camera
                    local cx, cy = camera.width / 2, camera.height / 2
                    local covered = scene.ui
                        and (scene.ui:hit(cx, cy) or scene.ui:blocksWorldClick(cx, cy))
                    for _, list in ipairs({
                        scene.renderer and scene.renderer.top or {},
                        scene.renderer and scene.renderer.transparent or {},
                    }) do
                        for _, board in ipairs(list) do
                            if visualPanelAt(scene, board, cx, cy) then
                                covered = true
                            end
                        end
                    end
                    local detector = not covered
                        and scene.world
                        and require('../world.picking').detector(
                            scene.world,
                            camera,
                            cx,
                            cy
                        )
                    if detector then
                        detector:activate('action:Interact')
                    end
                end
            end
        end
        if self.actions.listeners.Move then
            self.actions.listeners.Move(self.scene, movement, dt)
            return
        end
        if self.scene.character and not self.scene.freeDebugCamera then
            self.scene.character:setMove(x, z)
            return
        end
        if not hasWorldCamera(self.scene) then
            return
        end
        self.scene.camera:move(x, z, movement[2], dt, self.layout.speed, self.layout.verticalSpeed)
    end
end

return Movement
