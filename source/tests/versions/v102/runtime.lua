local T = {}

local function extra(test)
    local scene = assert(test.manager:switch(require('source.game.runtime.game').new, 'combined'))
    local ui, g = scene.ui, love.graphics
    for _, density in ipairs({ 1, 1.25, 1.5, 1.75, 2 }) do
        ui:setDensity(density)
        test:check(
            ui.density == density and ui:font(18):getDPIScale() == density,
            'Fonts retain exact target DPI ' .. density
        )
    end
    local Quality = require('source.engine.graphics.quality.renderQuality')
    local density = Quality.resolve(
        3840,
        2160,
        1,
        0,
        { texturesize = 8192, canvasmsaa = 8 },
        Quality.defaultPixels(),
        100663296
    )
    test:check(density == 1, 'Desktop default budgets preserve native 4K without downscaling')
    ui:setDensity(1)
    local label = ui:text({
        position = { 0, 10.3, 0, 12.7 },
        size = { 0, 240, 0, 50 },
        text = 'Pixel origin',
        align = 'left',
        verticalAlign = 'top',
        fontSize = 18,
    }, ui.content)
    ui:layout()
    local Text = require('source.engine.ui.drawing.text')
    local original = g.draw
    for _, targetDensity in ipairs({ 1, 1.25, 2 }) do
        local canvas = g.newCanvas(400, 100, { dpiscale = targetDensity })
        local x, y
        g.push('all')
        g.setCanvas({ canvas, stencil = true })
        g.origin()
        g.translate(0.2, 0.4)
        g.scale(1.1)
        g.draw = function(drawable, px, py, ...)
            if drawable:typeOf('Text') then
                x, y = g.transformPoint(px, py)
            end
            return original(drawable, px, py, ...)
        end
        local ok, err = pcall(Text.drawLabel, ui, label)
        g.draw = original
        g.pop()
        canvas:release()
        assert(ok, err)
        test:check(
            x
                and math.abs(x * targetDensity - math.floor(x * targetDensity + 0.5)) < 0.0001
                and math.abs(y * targetDensity - math.floor(y * targetDensity + 0.5)) < 0.0001,
            'Text origin lands on physical pixels at target DPI ' .. targetDensity
        )
    end
    local node = ui:container({ backgroundTransparency = 1, size = { 0, 20, 0, 20 } }, ui.content)
    ui:layout()
    local rectangle, calls = g.rectangle, 0
    g.rectangle = function(...)
        calls = calls + 1
        return rectangle(...)
    end
    node:drawSelf(ui)
    g.rectangle = rectangle
    test:check(calls == 0, 'Fully transparent built-in backgrounds submit no rectangle')
    node.backgroundTransparency = 0
    g.rectangle = function(...)
        calls = calls + 1
        return rectangle(...)
    end
    node:drawSelf(ui)
    g.rectangle = rectangle
    test:check(calls == 1, 'Visible backgrounds keep their draw')
    local shader =
        g.newShader('vec4 effect(vec4 c, Image t, vec2 uv, vec2 p) { return vec4(1.0); }')
    g.push('all')
    g.setShader(shader)
    node.backgroundTransparency = 1
    g.rectangle = function(...)
        calls = calls + 1
        return rectangle(...)
    end
    node:drawSelf(ui)
    g.rectangle = rectangle
    g.pop()
    shader:release()
    test:check(calls == 2, 'Inherited shaders can still paint zero-alpha backgrounds')
    local parent = ui:container(
        { position = { 0, 0, 0, 0 }, size = { 0, 100, 0, 100 }, clip = true },
        ui.content
    )
    local row = ui:container({ position = { 0, 0, 0, 200 }, size = { 0, 100, 0, 40 } }, parent)
    local corner = ui:create('UICorner', { radius = { 0, 8 } }, row)
    ui:layout()
    calls = 0
    g.rectangle = function(...)
        calls = calls + 1
        return rectangle(...)
    end
    g.push('all')
    g.setShader()
    ui:drawNode(row)
    g.pop()
    g.rectangle = rectangle
    test:check(calls == 0, 'Scrolled-out rounded rows skip stencil and background work')
    corner:destroy()
    row.backgroundTransparency = 0
    ui:layout()
    g.rectangle = function(...)
        calls = calls + 1
        return rectangle(...)
    end
    g.push('all')
    g.setShader()
    ui:drawNode(row)
    g.pop()
    g.rectangle = rectangle
    test:check(calls == 1, 'Unrounded containers retain overflow-capable traversal')
    local w, r = scene.world, scene.renderer
    w.environment.shadows.enabled = false
    w.environment.debug.gizmos.enabled = false
    w.environment.render.frameCache = false
    w.environment.render.depthPrepass = false
    w.environment.lightSettings.cullInvisible = false
    w.environment.lightSettings.selectionHoldSeconds = 0
    local lights = {}
    for _, light in ipairs(w.lights) do
        lights[#lights + 1] = light
    end

    local function capture(general)
        r.forceGeneralShader = general
        r.lights.nextSelection = -1
        for _, light in ipairs(lights) do
            light.nextUpdate = -1
        end
        r:draw(w, scene.camera, 10, true)
        local data = r.canvas:newImageData()
        local bytes = data:getString()
        data:release()
        return bytes
    end
    for _, count in ipairs({ 0, 1, 8, 32, 1 }) do
        for i, light in ipairs(lights) do
            light.enabled = i <= count
            light.rainbow = false
        end
        w.environment.lightSettings.maxActiveLights = 32
        local a, b = capture(true), capture(false)
        test:check(
            r.lights.count == math.min(count, #lights),
            'Requested light-count transition reaches GPU slots: ' .. count
        )
        local maximum = 0
        for i = 1, #a do
            maximum = math.max(maximum, math.abs(a:byte(i) - b:byte(i)))
        end
        test:check(
            maximum <= 1,
            'Light-count shader matches general program within one byte; requested ' .. count
        )
    end
    r.forceGeneralShader = false
    local conf = { window = {}, modules = {} }
    love.conf(conf)
    test:check(conf.window.vsync == 0, 'Normal startup disables VSync')
end

function T.new(manager)
    local base = require('source.tests.versions.v101.runtime').new(manager)
    local finish = base.finish
    base.finish = function(test)
        extra(test)
        finish(test)
        print('PASSED ' .. test.count .. ' v102 regression/integration checks')
    end
    return base
end

return T
