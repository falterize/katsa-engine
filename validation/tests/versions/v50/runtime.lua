local Base = require('validation.tests.versions.v49.runtime')

local Runtime = {}
Runtime.__index = Runtime

function Runtime.new(manager)
    return setmetatable({ manager = manager, base = Base.new(manager), checks = 0 }, Runtime)
end

function Runtime:check(ok, message)
    assert(ok, message)
    self.checks = self.checks + 1
    print('PASS v50 ' .. message)
end

function Runtime:update(dt)
    if not self.started then
        self.started = true
        require('validation.tests.versions.v50.native')(self)
    end
    self.base:update(dt)
    if self.base.base.frame % 3 ~= 0 or not self.base.base.scene then
        return
    end
    local scene = self.base.base.scene
    local ws = scene.workspace
    local ui = scene.ui
    if scene.zone == 'uiGallery' then
        for _, node in ipairs(scene.demo.root:getDescendants()) do
            if node.modifier then
                ws:select(node)
                self:check(
                    #ws.fields >= (node:isA('UICorner') and 4 or 5),
                    'Modifier properties available for ' .. node.className
                )
                if node:isA('UIGradient') then
                    for _, field in ipairs(ws.fields) do
                        if field.key == 'colorStops' then
                            ws:openPopup(field)
                            local popup = ws.popup
                            self:check(
                                popup.body.length == 510,
                                'Gradient point editor opens outside inspector clipping'
                            )
                            local old = node.colorStops[1].color[1]
                            popup:setRGB({ 0.3, 0.7, 0.2 })
                            popup:close(false)
                            self:check(
                                node.colorStops[1].color[1] == old,
                                'Gradient Cancel restores deep stop data'
                            )
                            ws:openPopup(field)
                            popup = ws.popup
                            local before = #node.colorStops
                            ui:scrollBy(popup.body, 9999)
                            ui:layout()
                            for _, child in ipairs(popup.body.children) do
                                if child.text == 'Add midpoint' then
                                    local x, y = ui:position(child)
                                    scene.input:press('gradient-touch', x + 8, y + 8)
                                    scene.input:release('gradient-touch', x + 8, y + 8)
                                    break
                                end
                            end
                            self:check(
                                #node.colorStops == before + 1,
                                'Gradient Add midpoint accepts touch and preserves ordered points'
                            )
                            ui:scrollBy(popup.body, 9999)
                            ui:layout()
                            for _, child in ipairs(popup.body.children) do
                                if child.text == 'Remove' then
                                    local x, y = ui:position(child)
                                    scene.input:press('gradient-touch', x + 8, y + 8)
                                    scene.input:release('gradient-touch', x + 8, y + 8)
                                    break
                                end
                            end
                            self:check(
                                #node.colorStops == before,
                                'Gradient Remove accepts touch and preserves minimum stop count'
                            )
                            popup:close(false)
                        end
                    end
                end
            end
        end
    elseif scene.zone == 'physics' or scene.zone == 'collisionModels' then
        self:check(
            #scene.demo.toolbar.children >= 3,
            'Lab panel contains real controls and explanatory content'
        )
        local mesh = scene.world.objects[2]
        for _, child in ipairs(require('source.engine.editor.tree.traversal').children(mesh)) do
            if child.className == 'Body3D' then
                ws:select(child)
                for _, field in ipairs(ws.fields) do
                    if field.key == 'linearDamping' then
                        self:check(
                            field.hint and field.hint:find('1/second', 1, true),
                            'Body3D damping includes units in inspector hint'
                        )
                        ws:showHint(field)
                        self:check(
                            ws.popup.readOnlyHint and ws.popup.body.length > 80,
                            'Body3D tooltip opens a readable scrollable modal'
                        )
                        ws.popup:close(false)
                        local old = child._editorTarget[field.key]
                        self:check(
                            require('source.engine.editor.inspectors.properties').set(
                                scene,
                                child._editorTarget,
                                field,
                                '0.25'
                            ),
                            'Body3D property editor accepts finite nonnegative damping'
                        )
                        self:check(
                            math.abs(mesh.body.raw:getLinearDamping() - 0.25) < 1e-8,
                            'Inspector Body3D edit updates the native backend immediately'
                        )
                        require('source.engine.editor.inspectors.properties').set(
                            scene,
                            child._editorTarget,
                            field,
                            tostring(old)
                        )
                    end
                end
            end
        end
        local panel = scene.demo.toolbar
        local toggle = scene.demo.toolbarToggle
        local _, y = ui:position(panel)
        toggle.onPress()
        ui:layout()
        self:check(
            not panel.visible and ui:hit(panel._x + 5, y + 5) ~= panel,
            'Collapsed panel releases old input rectangle'
        )
        toggle.onPress()
        self:check(panel.visible, 'Lab toggle expands content')
    elseif scene.zone == 'collisionBox' then
        scene.demo.focusButton.onPress()
        scene.renderer:prepare(scene.world, scene.camera, scene.time)
        local board = scene.demo.board
        self:check(
            board.sizeMode == 'World3D'
                and board.screenX - board.screenWidth * 0.5 >= 0
                and board.screenX + board.screenWidth * 0.5 <= ui.width,
            'Collision controls remain world-sized and can be focused in portrait'
        )
    elseif scene.zone == 'surfaceGallery' then
        ws:select(scene.demo.attachmentBoard)
        for _, field in ipairs(ws.fields) do
            if field.key == 'adornee' then
                ws:openPopup(field)
                self:check(
                    #ws.popup.body.children > 2,
                    'Adornee node picker includes live spatial supports'
                )
                ws.popup:close(false)
            end
        end
        self:check(
            scene.demo.attachmentBoard.adornee == scene.demo.attachment,
            'Moving example uses an independent Attachment3D support'
        )
        local board = scene.demo.attachmentBoard
        local p = board.worldPosition
        scene.camera.position = { p[1], p[2], p[3] - 140 }
        scene.camera.rotation = { 0, 0, 0 }
        scene.renderer:prepare(scene.world, scene.camera, scene.time)
        local wx, wy, wz =
            require('source.engine.math.math3d').transform(board.matrix, 0, 0.5 - 74 / 180, 0)
        local x, y = scene.camera:project({ wx, wy, wz })
        local old = scene.demo.attachmentClicks
        scene.input:press('mouse', x, y)
        scene.input:release('mouse', x, y)
        scene.input:press('touch-probe', x, y)
        scene.input:release('touch-probe', x, y)
        self:check(
            scene.demo.attachmentClicks == old + 2,
            'Moving Attachment3D BillboardUI accepts mouse and touch through scene input'
        )
    end
    if self.base.base.index == 112 then
        print('PASSED ' .. self.checks .. ' focused v50 native assertions')
    end
end

function Runtime:draw()
    self.base:draw()
end

return Runtime
