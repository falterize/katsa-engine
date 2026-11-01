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
    local function near(a, b)
        return math.abs(a - b) < 0.02
    end
    local function rgb(data, x, y, r, gr, b)
        local pr, pg, pb = data:getPixel(x, y)
        return near(pr, r) and near(pg, gr) and near(pb, b)
    end

    -- backbuffer clear + screenshot
    g.clear(1, 0, 0, 1)
    local shot
    g.captureScreenshot(function(image)
        shot = image
    end)
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
    T.check(rgb(data, 4, 4, 0, 1, 0) and rgb(data, 24, 24, 0, 0, 1),
        'canvas keeps top-left at row 0')
    T.check(rgb(data, 24, 4, 0, 0, 1) and rgb(data, 4, 24, 0, 0, 1),
        'canvas rectangle covers only its area')

    -- drawing the canvas to the backbuffer keeps the orientation
    g.clear(0, 0, 0, 1)
    g.setColor(1, 1, 1, 1)
    g.draw(canvas, 0, 0)
    g.captureScreenshot(function(image)
        shot = image
    end)
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
    T.check(rgb(raw, 32, 61, 1, 0, 0) and rgb(raw, 32, 2, 0, 0, 0),
        'raw NDC output is not flipped for canvases')

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
    T.check(drawn('back') == false and drawn('front') == true,
        'canvas cull mode follows the flipped winding')

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
    T.check(rgb(tr, 40, 8, 0, 1, 1) and rgb(tr, 60, 20, 0, 0, 0) and rgb(tr, 8, 8, 0, 0, 0),
        'translate and scale')

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
    T.check(rgb(im, 4, 4, 1, 0,
        0) and rgb(im, 12, 4, 0, 1, 0) and rgb(im, 4, 12, 0, 0, 1) and rgb(im, 12, 12, 1, 1, 1),
        'image draws with nearest filtering')

    -- text
    local font = g.newFont(16, 'normal', 1)
    local w = font:getWidth('Hello')
    T.check(w > 30 and w < 60 and font:getHeight() >= 16 and font:getHeight() <= 22,
        'font metrics are plausible')
    T.check(font:getWidth('HH') > font:getWidth('H') and font:getWidth('') == 0,
        'font width grows with text')
    local _, lines = font:getWrap('one two three four', font:getWidth('three four') + 1)
    T.check(#lines == 2 and lines[1] == 'one two' and lines[2] == 'three four',
        'getWrap breaks at spaces')
    local _, long = font:getWrap('abcdefghijklmnop', font:getWidth('abcd') + 1)
    T.check(#long >= 3, 'getWrap splits words that are too long')
    g.setCanvas(target)
    g.clear(0, 0, 0, 1)
    g.setFont(font)
    g.setColor(1, 1, 1, 1)
    g.print('MMMM', 2, 2)
    g.flushBatch()
    g.setCanvas()
    local tx = target:newImageData()
    local lit = 0
    for y = 0, 24 do
        for x = 0, 50 do
            if tx:getPixel(x, y) > 0.5 then
                lit = lit + 1
            end
        end
    end
    T.check(lit > 80 and tx:getPixel(60, 60) == 0, 'print draws glyph coverage')
    g.setCanvas(target)
    g.clear(0, 0, 0, 1)
    g.printf('MM', 0, 2, 64, 'right')
    g.flushBatch()
    g.setCanvas()
    local right = target:newImageData()
    local leftHalf, rightHalf = 0, 0
    for y = 0, 24 do
        for x = 0, 63 do
            if right:getPixel(x, y) > 0.5 then
                if x < 32 then
                    leftHalf = leftHalf + 1
                else
                    rightHalf = rightHalf + 1
                end
            end
        end
    end
    T.check(rightHalf > 20 and leftHalf == 0, 'printf aligns right')
    local text = g.newText(font, 'abc')
    T.check(math.abs(text:getWidth() - font:getWidth('abc')) < 0.01, 'Text reports the font width')

    -- A released canvas must not leave a cached framebuffer behind: GL reuses the texture id.
    for round = 1, 3 do
        local reused = g.newCanvas(16, 16, { dpiscale = 1 })
        g.setCanvas({ reused, stencil = true })
        g.clear(0.2, 0.4, 0.6, 1)
        g.setCanvas()
        local reusedData = reused:newImageData()
        T.check(rgb(reusedData, 2, 2, 0.2, 0.4, 0.6),
            'canvas ' .. round .. ' keeps its clear color after reuse')
        reused:release()
        g.present()
    end

    -- statistics follow creation and release
    local before = g.getStats()
    local counted = g.newCanvas(32, 32, { dpiscale = 1 })
    local during = g.getStats()
    T.check(during.canvases == before.canvases + 1
        and during.texturememory == before.texturememory + 32 * 32 * 4,
        'canvas creation is counted in getStats')
    counted:release()
    local after = g.getStats()
    T.check(after.canvases == before.canvases and after.texturememory == before.texturememory,
        'canvas release is subtracted from getStats')

    local name, version = g.getRendererInfo()
    T.check(name:find('OpenGL') and #version > 0, 'renderer info')
    platform:close()
end
