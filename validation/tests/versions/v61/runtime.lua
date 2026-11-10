local Test = {}
Test.__index = Test

function Test.new(manager)
    katsa.errorhandler = function(message)
        print('FAILED v61 ' .. tostring(message))
        return function()
            katsa.event.quit(1)
        end
    end
    return setmetatable({ manager = manager, frame = 0, count = 0 }, Test)
end

function Test:check(ok, message)
    assert(ok, message)
    self.count = self.count + 1
    print('PASS v61 ' .. message)
end

function Test:load(zone)
    local scene, err = self.manager:switch(require('source.game.runtime.game').new, zone)
    assert(scene, err)
    self.scene = scene
    scene:update(0.016, 0.016)
    return scene
end

local function field(node, key)
    for _, f in ipairs(require('source.engine.editor.inspectors.properties').list(node)) do
        if f.key == key then
            return f
        end
    end
    error('Missing property ' .. key)
end

local function button(popup, text)
    for _, n in ipairs(popup.body.children) do
        if n.text == text and n:hasConnections('press') then
            return n
        end
    end
    error('Missing button ' .. text)
end

function Test:update()
    self.frame = self.frame + 1
    if self.frame == 1 then
        katsa.window.setMode(960, 540, { vsync = 0, stencil = 8, depth = 24 })
        local scene = self:load('animationLab')
        local ramp =
            scene.world:create('Ramp', { mode = 'Animated', playbackTime = 0.2 }, scene.demo.body)
        self:check(
            ramp.application == nil and ramp.propertySchema.application == nil,
            'Applications removed from public Ramp API'
        )
        scene.workspace:toggle(true)
        scene.workspace:select(ramp)
        scene.workspace:openPopup(field(ramp, 'goals'))
        local popup = scene.workspace.popup
        button(popup, '+ Add goal'):press()
        button(popup, 'position'):press()
        self:check(
            ramp.goals.position and #ramp.bindings.position == 2,
            'Empty Goals editor adds a selected target property'
        )
        ramp.goals.position = { 9, 15, 0 }
        ramp.bindings.position[2].value = { 9, 15, 0 }
        self.capture = 'goals'
        self.ramp = ramp
    elseif self.frame == 2 then
        local scene = self.scene
        local popup = scene.workspace.popup
        popup:close(false)
        self:check(
            next(self.ramp.goals) == nil and next(self.ramp.bindings) == nil,
            'Cancel restores Goals and associated timelines together'
        )
        self.ramp:addGoal('position', { 9, 15, 0 }):play()
        scene.world:updateNodes(0.2)
        self:check(
            scene.demo.body.position[1] == 9,
            'Added multi-component goal plays through Tween'
        )
        scene.workspace:select(self.ramp)
        scene.workspace:openPopup(field(self.ramp, 'points'))
        popup = scene.workspace.popup
        local graph = popup.graph
        self:check(
            graph and graph.dragCapture,
            'Points graph explicitly captures its touch gesture'
        )
        button(popup, '+ Add point'):press()
        self:check(
            #self.ramp.points == 3 and graph.selected == 2,
            'Explicit Add point inserts and selects time 0.5'
        )
        local model = require('source.engine.editor.curves.sequenceModel')
        model.time(self.ramp.points, 2, 0.35)
        self:check(
            self.ramp.points[2].time == 0.35 and not pcall(model.time, self.ramp.points, 2, 1.1),
            'Point time editing enforces the normalized timeline'
        )
        scene.ui:layout()
        local x = (graph._x + graph._width * 0.35) * scene.ui.scale + scene.ui.offsetX
        local y = (graph._y + graph._height * 0.5) * scene.ui.scale + scene.ui.offsetY
        local scroll = popup.body.scrollY
        scene.input:press('curve', x, y)
        self:check(
            scene.input.captures.curve and scene.input.captures.curve.node == graph,
            'Pointer hits the timeline graph itself'
        )
        scene.input:move('curve', x, y + 25)
        scene.input:release('curve', x, y + 25)
        self:check(
            popup.body.scrollY == scroll and scene.input.captures.curve == nil,
            'Vertical graph drag does not turn into ScrollFrame scrolling'
        )
        self.capture = 'points'
    elseif self.frame == 3 then
        local scene = self:load('uiGallery')
        local node = scene.ui:container({ size = { 0, 100, 0, 50 } }, scene.ui.content)
        local ramp = scene.ui:create(
            'Ramp',
            { goals = { backgroundColor = { 1, 0, 0 }, backgroundTransparency = 1 } },
            node
        )
        scene.ui:layout()
        self:check(
            ramp:isSpatialGradient() and node._backgroundGradient,
            'Static UI color goals infer spatial gradient without Applications'
        )
        local stops = ramp:gradientStops('backgroundColor')
        self:check(
            stops[#stops].transparency == 1,
            'Transparency goal reaches its own alpha endpoint'
        )
        local stroke =
            scene.ui:create('UIStroke', { color = { 1, 1, 1 }, thickness = { 0, 2 } }, node)
        local outline = scene.ui:create('Ramp', { goals = { color = { 0, 1, 0 } } }, stroke)
        scene.ui:layout()
        self:check(
            stroke._backgroundGradient and outline:isSpatialGradient(),
            'Stroke supports its independent color Goals'
        )
        self.capture = 'ui'
    elseif self.frame == 4 then
        local scene = self:load('shaderLab')
        local demo = scene.demo
        demo.default.enabled = true
        demo.wave.enabled = true
        demo.pixel3D.enabled = true
        scene:update(0.016, 0.016)
        self:check(
            demo.pixelSize == 24 and demo.pixel.enabled,
            'Showcase starts with clearly visible 24-pixel blocks'
        )
        self:check(
            scene.statsLayer.zIndex > scene.workspace.group.zIndex,
            'Stats overlay sits above Workspace and shader showcase'
        )
        self.capture = 'shaders-hooks'
    elseif self.frame == 5 then
        local scene = self.scene
        self:check(
            scene.demo.preview._world.renderer.stats.objects > 0,
            'Processed viewport renders its own 3D world'
        )
        scene.demo.preset = 'Both'
        scene.demo:sync()
        scene.showStats = true
        scene:update(0.016, 0.016)
        scene.demo.default.enabled = false
        scene.demo.wave.enabled = false
        scene.demo.pixel3D.enabled = false
        self.capture = 'stats'
    elseif self.frame == 6 then
        local scene = self:load('particles')
        self:check(
            scene.demo.emitter.lifetimeRamp:isLifetime(),
            'Particle lifetime Ramp is inferred from its owner'
        )
        local candidates =
            require('source.engine.animation.rampGoals').candidates(scene.demo.emitter.lifetimeRamp)
        self:check(
            #candidates == 4,
            'Lifetime Goals exposes size, color, transparency and rotation'
        )
        self.capture = 'particles'
    elseif self.frame == 7 then
        katsa.window.setMode(400, 760, { vsync = 0, stencil = 8, depth = 24 })
        local scene = self:load('shaderLab')
        scene.demo.preset = 'CRT'
        scene.demo:sync()
        scene:update(0.016, 0.016)
        self:check(
            scene.demo.pixel._width > 0 and scene.demo.pixel._height > 0,
            'Portrait showcase retains positive comparison viewport sizes'
        )
        self.capture = 'portrait'
    elseif self.frame == 8 then
        self:check(
            #self.manager.journal.entries == 0,
            'Focused scene transitions leave an empty error journal'
        )
        print('PASSED ' .. self.count .. ' focused v61 checks')
        katsa.event.quit()
    end
end

function Test:draw()
    if not self.capture then
        return
    end
    local name = self.capture
    self.capture = nil
    katsa.graphics.captureScreenshot(function(image)
        local data = image:encode('png')
        local file = assert(
            io.open(katsa.filesystem.getSource() .. '/docs/previews/v61/' .. name .. '.png', 'wb')
        )
        file:write(data:getString())
        file:close()
        data:release()
        image:release()
    end)
end

return Test
