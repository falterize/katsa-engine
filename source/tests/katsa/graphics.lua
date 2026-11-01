-- Renders on a real GL context (SDL2 window; needs a display such as Xvfb) and checks pixels.
return function(T)
    local ok, Platform = pcall(require, 'source.katsa.platform.sdl2')
    local platform = ok and Platform.new({ title = 'graphics test' })
    if not platform then
        return T.skip('graphics: SDL2 platform unavailable')
    end
    local katsa = require('source.katsa')
    katsa.attachPlatform(platform)
    local opened, reason = katsa.window.setMode(64, 64, { vsync = 0 })
    if not opened then
        platform:close()
        return T.skip('graphics: no window (' .. tostring(reason) .. ')')
    end
    local g = katsa.graphics
    local function near(a, b) return math.abs(a - b) < 0.02 end
    local function rgb(data, x, y, r, gr, b)
        local pr, pg, pb = data:getPixel(x, y)
        return near(pr, r) and near(pg, gr) and near(pb, b)
    end

    -- backbuffer clear + screenshot
    g.clear(1, 0, 0, 1)
    local shot
    g.captureScreenshot(function(image) shot = image end)
    g.present()
    T.check(shot and rgb(shot, 10, 10, 1, 0, 0), 'backbuffer clear and screenshot')

    -- canvas orientation: rows run top to bottom
    local canvas = g.newCanvas(32, 32, { dpiscale = 1 })
    g.setCanvas(canvas)
    g.clear(0, 0, 1, 1)
    g.setColor(0, 1, 0, 1)
    g.rectangle('fill', 0, 0, 16, 16)
    g.flushBatch()
    g.setCanvas()
    local data = canvas:newImageData()
    T.check(rgb(data, 4, 4, 0, 1, 0) and rgb(data, 24, 24, 0, 0, 1), 'canvas keeps top-left at row 0')
    T.check(rgb(data, 24, 4, 0, 0, 1) and rgb(data, 4, 24, 0, 0, 1), 'canvas rectangle covers only its area')

    -- drawing the canvas to the backbuffer keeps the orientation
    g.clear(0, 0, 0, 1)
    g.setColor(1, 1, 1, 1)
    g.draw(canvas, 0, 0)
    g.captureScreenshot(function(image) shot = image end)
    g.present()
    T.check(rgb(shot, 4, 4, 0, 1, 0) and rgb(shot, 24, 24, 0, 0, 1) and rgb(shot, 50, 50, 0, 0, 0),
        'canvas draw to backbuffer is upright')

    -- raw clip-space output is not flipped (top half of NDC lands in the last canvas rows)
    local shader = g.newShader([[
        vec4 position(mat4 tp, vec4 vp) { return vec4(vp.xy, 0.0, 1.0); }
        vec4 effect(vec4 c, Image t, vec2 uv, vec2 sc) { return vec4(1.0, 0.0, 0.0, 1.0); }
    ]])
    local half = g.newMesh({ { -1, 0 }, { 1, 0 }, { 1, 1 }, { -1, 1 } }, 'fan')
    local target = g.newCanvas(64, 64, { dpiscale = 1 })
    g.setCanvas(target)
    g.clear(0, 0, 0, 1)
    g.setShader(shader)
    g.draw(half)
    g.setShader()
    g.setCanvas()
    local raw = target:newImageData()
    T.check(rgb(raw, 32, 61, 1, 0, 0) and rgb(raw, 32, 2, 0, 0, 0), 'raw NDC output is not flipped for canvases')

    -- culling: canvas rendering flips front faces
    local ccw = g.newMesh({ { -1, -1 }, { 1, -1 }, { 0, 1 } }, 'triangles')
    local function drawn(cull)
        g.setCanvas(target)
        g.clear(0, 0, 0, 1)
        g.setShader(shader)
        g.setMeshCullMode(cull)
        g.draw(ccw)
        g.setMeshCullMode('none')
        g.setShader()
        g.setCanvas()
        return target:newImageData():getPixel(32, 32) > 0.5
    end
    T.check(drawn('back') == false and drawn('front') == true, 'canvas cull mode follows the flipped winding')

    -- stencil
    g.setCanvas({ target, stencil = true })
    g.clear(0, 0, 0, 1, 0)
    g.stencil(function() g.rectangle('fill', 0, 0, 32, 64) end, 'replace', 1)
    g.setStencilTest('equal', 1)
    g.setColor(1, 1, 0, 1)
    g.rectangle('fill', 0, 0, 64, 64)
    g.setStencilTest()
    g.flushBatch()
    g.setCanvas()
    local st = target:newImageData()
    T.check(rgb(st, 10, 10, 1, 1, 0) and rgb(st, 50, 10, 0, 0, 0), 'stencil test limits drawing')

    -- scissor, blend
    g.setCanvas(target)
    g.clear(0, 0, 0, 1)
    g.setScissor(0, 0, 16, 16)
    g.setColor(1, 1, 1, 1)
    g.rectangle('fill', 0, 0, 64, 64)
    g.setScissor()
    g.setBlendMode('add')
    g.setColor(0.5, 0.25, 0, 1)
    g.rectangle('fill', 32, 32, 16, 16)
    g.setBlendMode('alpha')
    g.flushBatch()
    g.setCanvas()
    local sc = target:newImageData()
    T.check(rgb(sc, 8, 8, 1, 1, 1) and rgb(sc, 30, 8, 0, 0, 0), 'scissor clips drawing')
    T.check(rgb(sc, 40, 40, 0.5, 0.25, 0), 'additive blend')

    -- transforms
    g.setCanvas(target)
    g.clear(0, 0, 0, 1)
    g.push()
    g.translate(32, 0)
    g.scale(2, 2)
    g.setColor(0, 1, 1, 1)
    g.rectangle('fill', 0, 0, 8, 8)
    g.pop()
    g.flushBatch()
    g.setCanvas()
    local tr = target:newImageData()
    T.check(rgb(tr, 40, 8, 0, 1, 1) and rgb(tr, 60, 20, 0, 0, 0) and rgb(tr, 8, 8, 0, 0, 0), 'translate and scale')

    -- images
    local img = g.newImage(require('source.katsa.image').newImageData(2, 2, 'rgba8',
        string.char(255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255)))
    img:setFilter('nearest')
    g.setCanvas(target)
    g.clear(0, 0, 0, 1)
    g.setColor(1, 1, 1, 1)
    g.draw(img, 0, 0, 0, 8, 8)
    g.flushBatch()
    g.setCanvas()
    local im = target:newImageData()
    T.check(rgb(im, 4, 4, 1, 0, 0) and rgb(im, 12, 4, 0, 1, 0) and rgb(im, 4, 12, 0, 0, 1) and rgb(im, 12, 12, 1, 1, 1),
        'image draws with nearest filtering')

    local name, version = g.getRendererInfo()
    T.check(name:find('OpenGL') and #version > 0, 'renderer info')
    platform:close()
end
