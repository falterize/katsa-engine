local Test = {}
Test.__index = Test

function Test.new(manager)
    katsa.errorhandler = function(message)
        print('FAILED v62 ' .. tostring(message))
        return function()
            katsa.event.quit(1)
        end
    end
    return setmetatable({ manager = manager, frame = 0, count = 0 }, Test)
end

function Test:check(ok, message)
    assert(ok, message)
    self.count = self.count + 1
    print('PASS v62 ' .. message)
end

function Test:load(zone)
    local scene, err = self.manager:switch(require('source.game.runtime.game').new, zone)
    assert(scene, err)
    self.scene = scene
    scene:update(0.016, 0.016)
    return scene
end

local function findField(node, key)
    for _, f in ipairs(require('source.engine.editor.inspectors.properties').list(node)) do
        if f.key == key then
            return f
        end
    end
end

function Test:update()
    self.frame = self.frame + 1
    if self.frame == 1 then
        katsa.window.setMode(960, 540, { vsync = 0, stencil = 8, depth = 24 })
        local scene = self.manager.stack[#self.manager.stack]
        assert(scene, 'Menu scene unavailable')
        scene.input:press('blank-menu', 959, 539)
        scene.input:move('blank-menu', 950, 530)
        scene.input:release('blank-menu', 950, 530)
        scene.input:hover(959, 539)
        self:check(
            not scene.renderer and scene.world.activeCamera == nil,
            'Menu background touch and hover work without a renderer'
        )
        self:check(
            require('source.engine.world.picking').raycast(scene.world, nil, 959, 539) == nil,
            'Missing camera cannot generate a world ray'
        )
        scene = self:load('animationLab')
        local camera, renderer = scene.world.root.currentCamera, scene.renderer
        scene.world.root.currentCamera = nil
        scene.renderer = nil
        scene.input:press('camera-free', 959, 539)
        scene.input:move('camera-free', 900, 500)
        scene.input:release('camera-free', 900, 500)
        scene.input:hover(959, 539)
        self:check(
            scene.input.cameraId == nil,
            'Camera-free world does not capture world look or picking'
        )
        local fired = false
        local button = scene.ui:button({
            position = { 0, 400, 0, 80 },
            size = { 0, 100, 0, 40 },
            text = 'UI test',
            zIndex = 500,
            onPress = function()
                fired = true
            end,
        }, scene.ui.content)
        scene.ui:layout()
        local x = (button._x + 50) * scene.ui.scale + scene.ui.offsetX
        local y = (button._y + 20) * scene.ui.scale + scene.ui.offsetY
        scene.input:press('ui', x, y)
        scene.input:release('ui', x, y)
        self:check(fired, 'Camera-free world still dispatches screen UI events')
        scene.world.root.currentCamera = camera
        scene.renderer = renderer
        local Sequence = require('source.engine.animation.sequence')
        local ramp = scene.world:create('Ramp', {
            mode = 'Animated',
            playbackTime = 1,
            interpolation = 'Curve',
            bindings = {
                position = Sequence.linear({ 0, 0, 0 }, { 10, 0, 0 }),
                rotation = Sequence.linear({ 0, 0, 0 }, { 0, 90, 0 }),
            },
        }, scene.demo.body)
        self.ramp = ramp
        self:check(
            findField(ramp, 'interpolation') == nil,
            'Ramp inspector no longer exposes duplicate Interpolation'
        )
        scene.workspace:toggle(true)
        scene.workspace:select(ramp)
        scene.workspace:openPopup(findField(ramp, 'goals'))
        local popup = scene.workspace.popup
        require('source.engine.editor.curves.sequenceEditor').open(popup, 'position')
        for _, n in ipairs(popup.body.children) do
            if n.text == 'Interpolation: Curve' then
                n.onPress()
                break
            end
        end
        self:check(
            ramp.bindings.position.interpolation == 'Linear'
                and ramp.bindings.rotation.interpolation == 'Curve',
            'Goal interpolation toggle changes only its own timeline'
        )
        popup:close(false)
        self:check(
            ramp.bindings.position.interpolation == 'Curve',
            'Cancel restores per-goal interpolation'
        )
        ramp.bindings.position.interpolation = 'Linear'
        ramp.bindings.rotation[1].outgoing = { 0.2, 0 }
        ramp.bindings.rotation[2].incoming = { 0.8, 0 }
        ramp:play()
        scene.world:updateNodes(0.25)
        self:check(
            math.abs(scene.demo.body.position[1] - 2.5) < 0.001
                and scene.demo.body.rotation[2] < 22.5,
            'Tween evaluates mixed Linear and Curve goal timelines independently'
        )
        ramp:stop()
        scene.workspace:select(ramp)
        scene.workspace:openPopup(findField(ramp, 'points'))
        local graph = scene.workspace.popup.graph
        ramp.points = { { time = 0, value = 0 }, { time = 1, value = 1 }, interpolation = 'Curve' }
        graph.points, graph.interpolation = ramp.points, 'Curve'
        scene.ui:layout()

        local function point(t, v)
            return (graph._x + t * graph._width) * scene.ui.scale + scene.ui.offsetX,
                (graph._y + (1 - v) * graph._height) * scene.ui.scale + scene.ui.offsetY
        end
        x, y = point(1 / 3, 1 / 3)
        graph:pointer(scene.ui, 'press', x, y, 'out')
        x, y = point(0.99, 0.1)
        graph:pointer(scene.ui, 'move', x, y, 'out')
        graph:pointer(scene.ui, 'release', x, y, 'out')
        self:check(
            ramp.points[1].outgoing[1] <= 2 / 3 + 1e-10 and pcall(Sequence.validate, ramp.points),
            'Outgoing handle cannot cross an implicit incoming handle'
        )
        graph.selected = 2
        x, y = point(2 / 3, 2 / 3)
        graph:pointer(scene.ui, 'press', x, y, 'in')
        x, y = point(0.01, 0.9)
        graph:pointer(scene.ui, 'move', x, y, 'in')
        graph:pointer(scene.ui, 'release', x, y, 'in')
        self:check(
            ramp.points[2].incoming[1] >= ramp.points[1].outgoing[1]
                and pcall(Sequence.validate, ramp.points),
            'Incoming handle cannot cross its opposite handle'
        )
        self:check(
            type(Sequence.evaluate(ramp.points, 0.5)) == 'number',
            'Edited Bezier curve evaluates without a render-time crash'
        )
    elseif self.frame == 2 then
        self.scene.workspace.popup:close(true)
        local scene = self:load('shaderLab')
        scene.input:press('shader-background', 959, 539)
        scene.input:release('shader-background', 959, 539)
        self:check(
            scene.demo.preview._world.root ~= scene.world.root,
            'Shader viewport worlds remain independent after input fix'
        )
    elseif self.frame == 3 then
        self:load('particles')
    elseif self.frame == 4 then
        self:check(
            #self.manager.journal.entries == 0,
            'Scene transitions and edited curve rendering leave no errors'
        )
        print('PASSED ' .. self.count .. ' focused v62 checks')
        katsa.event.quit()
    end
end

function Test:draw() end
return Test
