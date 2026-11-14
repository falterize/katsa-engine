-- Focused regressions for the changed inspector, culling and input paths.
local R = {}
R.__index = R

function R.new(manager)
    return setmetatable({ manager = manager, count = 0, frame = 0 }, R)
end

function R:check(ok, message)
    assert(ok, message)
    self.count = self.count + 1
    print('PASS v55 ' .. message)
end

function R:update()
    self.frame = self.frame + 1
    if self.frame == 1 then
        katsa.window.setMode(640, 360, { vsync = 0, depth = 24, stencil = 8 })
        local scene, err = self.manager:switch(require('source.game.runtime.game').new, 'physics')
        assert(scene, err)
        self.scene = scene
        local ws = scene.workspace
        ws:toggle(true)
        ws:update(0.3)
        local object
        for _, o in ipairs(scene.world.objects) do
            if o.physics then
                object = o
                break
            end
        end
        assert(object, 'Physics example requires a Mesh3D body')
        ws:select(object)
        local bodyRow
        for _, row in ipairs(require('source.engine.editor.tree.traversal').children(object)) do
            if row.className == 'Body3D' then
                bodyRow = row
            end
        end
        assert(bodyRow, 'Virtual Body3D row is missing')
        ws:select(bodyRow)
        self:check(
            ws.parentPathText == nil,
            'Mesh3D-to-Body3D selection clears the stale Parent widget'
        )
        local widget = ws.properties.children[1]
        ws.properties.scrollY = 70
        scene.ui:invalidate()
        scene.ui:layout()
        local scroll = ws.properties.scrollY
        for i = 1, 6 do
            ws:update(0.016)
        end
        self:check(
            ws.properties.children[1] == widget
                and not widget.destroyed
                and ws.properties.scrollY == scroll,
            'Body3D inspector remains stable across updates and preserves scroll'
        )
        scene.ui:pointer(ws.properties, 'press', 0, 80, 'body-finger')
        scene.ui:pointer(ws.properties, 'move', 0, 40, 'body-finger')
        self:check(
            ws.properties._scrollPointer == 'body-finger' and ws.properties.scrollY >= scroll,
            'Body3D properties accept finger scrolling'
        )
        scene.ui:pointer(ws.properties, 'cancel', 0, 0, 'body-finger')
        scene.ui:scrollBy(ws.properties, -100000)
        scene.ui:layout()
        local x = (ws.properties._x + 10) * scene.ui.scale + scene.ui.offsetX
        local y = (ws.properties._y + math.min(110, ws.properties._height - 10)) * scene.ui.scale
            + scene.ui.offsetY
        local initial = ws.properties.scrollY
        scene.input:press('actual-body', x, y)
        scene.input:move('actual-body', x, y - 30, 0, -30)
        ws:update(0.016)
        self:check(
            scene.input.captures['actual-body'] and ws.properties.scrollY > initial,
            'Body3D drag passes through the real Input capture path'
        )
        scene.input:release('actual-body', x, y - 30)
        local toggle
        for _, entry in ipairs(ws.propertyButtons) do
            if entry.field.key == 'isTrigger' then
                toggle = entry
            end
        end
        assert(toggle)
        local old = bodyRow.physics.settings.isTrigger or false
        toggle.button:press()
        ws:update(0.016)
        self:check(
            bodyRow.physics.settings.isTrigger == not old and not toggle.button.destroyed,
            'Body3D trigger editing survives the next inspector update'
        )
        local Properties = require('source.engine.editor.inspectors.properties')
        local typeField
        for _, field in ipairs(ws.fields) do
            if field.key == 'type' then
                typeField = field
            end
        end
        assert(Properties.set(scene, bodyRow._editorTarget, typeField, 'static'))
        ws:update(0.016)
        local gravity = false
        for _, field in ipairs(ws.fields) do
            if field.key == 'gravityScale' then
                gravity = true
            end
        end
        self:check(
            not gravity and ws.selected == bodyRow,
            'Body3D mode change refreshes conditional fields without losing selection'
        )
        ws:toggle(false)
        local ui = require('source.engine.ui').new(320, 240, scene.resources)
        local label = ui:text({ size = { 0, 40, 0, 20 }, text = 'Cache' }, ui.content)
        ui:layout()
        ui:layout()
        local passes = ui.layoutPasses
        ui:layout()
        self:check(ui.layoutPasses == passes, 'Unchanged UI does not repeat layout')
        label.size[2] = 75
        ui:layout()
        self:check(
            label._width == 75 and ui.layoutPasses == passes + 1,
            'In-place UDim2 edits invalidate cached layout'
        )
        local hidden = ui:container({ visible = false, size = { 0, 100, 0, 100 } }, ui.content)
        local child = ui:text({ size = { 0, 30, 0, 20 }, text = 'Hidden' }, hidden)
        ui:layout()
        child.size[2] = 60
        hidden.visible = true
        ui:layout()
        self:check(
            child._width == 60,
            'Showing a hidden subtree observes changes made while hidden'
        )
        ui:release()
        local A = require('source.engine.input.actions').new()
        A:bind('Move', { forward = 'i', back = 'k', left = 'j', right = 'l' })
        A:keypressed('i')
        A:keypressed('l')
        local v = A:updateMove(0, 0, 0, 0)
        self:check(
            math.abs(v[1] ^ 2 + v[3] ^ 2 - 1) < 0.0001 and v[3] > 0,
            'Move uses scene bindings and normalizes diagonal movement'
        )
        A:keypressed('space')
        A:keypressed('space')
        self:check(
            A:consume('Jump') and not A:consume('Jump'),
            'Jump press is consumed once despite key repeat'
        )
        A:look(4, 6)
        A:look(1, 2)
        A:updateMove(0, 0, 0, 0)
        self:check(
            A:value('Look')[1] == 5 and A:value('Look')[2] == 8,
            'Look accumulates pointer deltas'
        )
        A:updateMove(0, 0, 0, 0)
        self:check(A:value('Look')[1] == 0, 'Look deltas do not repeat on a later frame')
        A:trigger('Interact')
        A:reset()
        A:updateMove(0, 0, 0, 0)
        self:check(
            not A:consume('Interact') and A:value('Move')[3] == 0 and A:value('Jump') == false,
            'Reset clears held keys and pending actions'
        )
        scene.input.captures.a = { kind = 'joystick' }
        scene.input.joystickId = 'a'
        scene.input.axisX = 1
        scene.input.captures.b = { kind = 'camera' }
        scene.input.cameraId = 'b'
        scene.input:cancel('a')
        self:check(
            scene.input.cameraId == 'b' and scene.input.captures.b and scene.input.axisX == 0,
            'Cancelling one finger preserves the other finger ownership'
        )
        scene.input:keypressed('w')
        self.manager:focus(false)
        self.manager:focus(true)
        self:check(
            next(scene.input.captures) == nil and next(scene.input.actions.keys) == nil,
            'Focus loss clears pointers and action keys'
        )
        local picking = require('source.engine.world.picking')
        local original = picking.raycast
        local calls = 0
        picking.raycast = function(...)
            calls = calls + 1
            return original(...)
        end
        local result = picking.detector({ objects = {} }, scene.camera, 10, 10)
        picking.raycast = original
        self:check(result == nil and calls == 0, 'Scenes without detectors skip triangle picking')
        local profile = self.manager.profiler
        profile:sample('Disabled', 1)
        self:check(next(profile.samples) == nil, 'Disabled profiler stores no timing samples')
        profile.enabled = true
        profile:sample('Check', 2)
        self:check(profile.samples.Check.last == 2, 'Enabled profiler records observations')
        profile.enabled = false
        local journal = require('source.engine.debug.journal').new(2)
        for i = 1, 3 do
            journal:record('Test', i, object, 'test.lua')
        end
        self:check(
            #journal.entries == 2
                and journal.entries[2].node == object.name
                and journal.entries[2].script == 'test.lua',
            'Error journal is bounded and records node and script context'
        )
        local valid, errorMessage =
            pcall(require('source.engine.core.validate').vector, { 0 / 0, 0, 0 }, 'Probe', 3)
        self:check(
            not valid and errorMessage:find('Probe%[1%]'),
            'Optimized validation still rejects invalid components clearly'
        )
        self:check(
            pcall(require('source.engine.editor.debug.diagnostics').open, ws),
            'Diagnostics panel opens with profiler and error journal'
        )
        ws.popup:close(false)
    elseif self.frame == 3 then
        local scene, err = self.manager:switch(require('source.game.runtime.game').new, 'combined')
        assert(scene, err)
        self.scene = scene
        scene.renderer.maxMeshDistance = 1
        scene.renderer:prepare(scene.world, scene.camera, scene.time)
        self:check(
            scene.renderer.stats.distanceCulled > 0,
            'Mesh3D distance budget culls distant bounds'
        )
        scene.renderer.maxMeshDistance = 0
        local controls = scene.controls.joystick
        controls.custom = true
        controls.x, controls.y, controls.radius = 80, 90, 40
        scene:resize(katsa.graphics.getDimensions())
        self:check(
            controls.x == 80 and controls.y == 90 and controls.radius == 40,
            'Authored joystick placement survives resize'
        )
    elseif self.frame == 5 then
        local scene, err =
            self.manager:switch(require('source.game.runtime.game').new, 'nightPlayer')
        assert(scene, err)
        self.scene = scene
        local jumps = 0
        scene.input.actions:on('Jump', function()
            jumps = jumps + 1
        end)
        scene.input:trigger('Jump')
        scene.input:update(0)
        scene.input:update(0)
        self:check(jumps == 1, 'Game adapter dispatches a mobile action to scene gameplay once')
        self.manager.profiler.enabled = true
    elseif self.frame == 7 then
        self:check(
            self.manager.profiler.samples['Scene update']
                and self.manager.profiler.samples['Screen UI'],
            'Scene CPU profiler collects real update and render observations'
        )
        self.manager.profiler.enabled = false
        local scene, err = self.manager:switch(require('source.game.runtime.game').new, 'shadows')
        assert(scene, err)
        self.scene = scene
    elseif self.frame == 9 then
        local probe = require('source.engine.graphics.debug.shadowProbe').measure(
            self.scene.renderer,
            self.scene.world,
            self.scene.camera,
            self.scene.time,
            1
        )
        self:check(
            probe.withSampling >= 0 and probe.withoutSampling >= 0,
            'Local shadow rendering and readback probe run after shader simplification'
        )
        self:check(
            not self.scene.renderer.shadows.samplingDisabled
                and not self.scene.renderer.freezeShadowUpdates,
            'Shadow sampling probe restores renderer flags'
        )
        print('PASSED ' .. self.count .. ' targeted v55 checks and four live scene transitions')
        katsa.event.quit()
    end
end

function R:draw() end
return R
