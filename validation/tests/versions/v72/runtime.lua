local T = {}
T.__index = T

function T.new(manager)
    katsa.window.setMode(640, 360, { vsync = 0, depth = 24, stencil = 8 })
    katsa.errorhandler = function(err)
        print('FAILED v72 ' .. tostring(err))
        return function()
            return 1
        end
    end
    return setmetatable({ manager = manager, count = 0 }, T)
end

function T:check(ok, label)
    assert(ok, label)
    self.count = self.count + 1
    print('PASS v72 ' .. label)
end

function T:update()
    if self.done then
        return
    end
    self.done = true
    local scene = assert(self.manager:switch(require('source.game.runtime.game').new, 'combined'))
    scene.world.environment.shadows.enabled = false
    scene.world.environment.gizmos.enabled = false
    self:check(
        scene.world.environment.render.lightLoop == 'Direct',
        'Direct light iteration is the default'
    )

    local function render(mode)
        scene.world.environment.render.lightLoop = mode
        scene.renderer:draw(scene.world, scene.camera, scene.time)
        return scene.renderer.canvas:newImageData()
    end
    local a, b = render('Direct'), render('Masked')
    local maximum = 0
    for y = 0, a:getHeight() - 1 do
        for x = 0, a:getWidth() - 1 do
            local ar, ag, ab = a:getPixel(x, y)
            local br, bg, bb = b:getPixel(x, y)
            maximum = math.max(maximum, math.abs(ar - br), math.abs(ag - bg), math.abs(ab - bb))
        end
    end
    a:release()
    b:release()
    self:check(maximum < 0.005, 'Direct and Masked lighting preserve image output')
    self:check(
        #scene.world.objects == 401 and scene.renderer.lights.count == 32,
        'All stress geometry and selected lights are retained'
    )
    local shader = require('source.engine.graphics.pipeline.shaderVariants').get(
        scene.renderer,
        scene.world.objects[2]
    )
    self:check(shader:hasUniform('objectLights1'), 'Masked variant retains per-object light masks')
    render('Direct'):release()
    shader = require('source.engine.graphics.pipeline.shaderVariants').get(
        scene.renderer,
        scene.world.objects[2]
    )
    self:check(
        not shader:hasUniform('objectLights1'),
        'Direct variant compiles out mask decoding and attributes'
    )
    local crt = katsa.graphics.newShader('assets/shaders/examples/tvStatic.glsl')
    for _, size in ipairs({ { 1920, 1080 }, { 1080, 2400 }, { 2560, 1440 } }) do
        local w, h = unpack(size)
        local canvas = katsa.graphics.newCanvas(w, h)
        local white = scene.resources:image('white')
        crt:send('resolution', { w, h })
        crt:send('regionOrigin', { 0, 0 })
        crt:send('regionExtent', { w, h })
        crt:send('noiseStrength', 0.2)
        crt:send('scanlineStrength', 0.22)
        crt:send('distortion', 0.03)
        for _, time in ipairs({ 0, 23.25, 36000 }) do
            crt:send('time', time)
            katsa.graphics.push('all')
            katsa.graphics.setCanvas(canvas)
            katsa.graphics.origin()
            katsa.graphics.setScissor()
            katsa.graphics.setStencilTest()
            katsa.graphics.setDepthMode()
            katsa.graphics.setColor(1, 1, 1, 1)
            katsa.graphics.setBlendMode('replace')
            katsa.graphics.setShader(crt)
            katsa.graphics.draw(white, 0, 0, 0, w / white:getWidth(), h / white:getHeight())
            katsa.graphics.pop()
            local data = canvas:newImageData()
            local darkest = 1
            for y = 0, h - 1, 61 do
                for x = 0, w - 1, 61 do
                    local r = data:getPixel(x, y)
                    darkest = math.min(darkest, r)
                end
            end
            data:release()
            self:check(
                darkest > 0.5,
                'CRT keeps source visible at ' .. w .. 'x' .. h .. ' / time ' .. time
            )
        end
        canvas:release()
    end
    crt:release()
    local ui = require('source.engine.ui').new(1920, 1080, scene.resources):bindWorld(scene.world)
    ui.parent = scene.world.root
    local effect = ui:create('Shader2D', {
        position = { 0.1, 0, 0.1, 0 },
        size = { 0.8, 0, 0.8, 0 },
        backgroundColor = { 1, 1, 1 },
        shaderPath = 'assets/shaders/examples/tvStatic.glsl',
        uniforms = {
            resolution = { 1, 1 },
            regionOrigin = { 9999, 9999 },
            regionExtent = { 1, 1 },
            noiseStrength = 0.2,
            scanlineStrength = 0.22,
            distortion = 0.03,
        },
    }, ui.content)
    for _, size in ipairs({ { 1920, 1080 }, { 1080, 2400 }, { 640, 360 } }) do
        local w, h = unpack(size)
        ui.width, ui.height = w, h
        ui.time = 36000
        local target = katsa.graphics.newCanvas(w, h)
        katsa.graphics.push('all')
        katsa.graphics.setCanvas({ target, stencil = true })
        katsa.graphics.origin()
        katsa.graphics.setScissor()
        katsa.graphics.setStencilTest()
        katsa.graphics.clear(0.3, 0.3, 0.3, 1, 0)
        ui:draw()
        katsa.graphics.pop()
        local data = target:newImageData()
        local r, g, b = data:getPixel(math.floor(w * 0.5), math.floor(h * 0.5))
        data:release()
        target:release()
        self:check(
            r > 0.5 and g > 0.5 and b > 0.5,
            'Compositor refreshes stale CRT bounds after resize ' .. w .. 'x' .. h
        )
    end
    ui:destroy()
    self.manager:switch(require('source.game.runtime.menu').new)
    self:check(
        #self.manager.journal.entries == 0,
        'Scene and graphics cleanup has no journal errors'
    )
    print('PASSED ' .. self.count .. ' focused v72 checks')
    katsa.event.quit()
end

function T:draw() end
return T
