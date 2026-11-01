local Tests = {}
Tests.__index = Tests
function Tests.new(manager)
    return setmetatable({ manager = manager }, Tests)
end
function Tests:update() end
function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    local ffi = require('ffi')
    if ffi.os == 'Windows' then
        ffi.cdef(
            [[void *GetThreadDpiAwarenessContext(void); int GetAwarenessFromDpiAwarenessContext(void *);]]
        )
        local user = ffi.load('user32')
        local awareness =
            user.GetAwarenessFromDpiAwarenessContext(user.GetThreadDpiAwarenessContext())
        assert(awareness == 2, 'Windows must not bitmap-scale the game window')
        print('WINDOWS DPI AWARENESS', awareness)
    end
    print('DPI', love.graphics.getDPIScale(), love.graphics.getDimensions())
    local resources = self.manager.resources:scope()
    local ui = require('source.engine.ui').new(800, 600, resources)
    ui:setDensity(0.75)
    assert(ui:font(22):getDPIScale() == 0.75, 'Shrunken UI must rasterize at its target density')
    local node = ui:text({ text = 'Sharp aligned text', size = { 0, 271, 0, 49 } }, ui.content)
    ui:layout()
    love.graphics.push('all')
    love.graphics.scale(1.25)
    ui:drawRaw()
    love.graphics.pop()
    assert(node._textDrawables[1] ~= nil, 'Aligned text retains its glyph geometry')
    local image = resources:image('assets/textures/ui/litter.png')
    assert(image:getMipmapCount() > 1, 'Linear image variants must support mipmaps')
    local nearest = resources:imageVariant('assets/textures/ui/litter.png', true)
    assert(nearest:getFilter() == 'nearest', 'Pixel-art variants retain explicit nearest sampling')
    local mipmap = nearest:getMipmapFilter()
    print('PIXEL MIPMAP', tostring(mipmap))
    assert(mipmap == nil or mipmap == 'none', 'Pixel-art variants disable mipmap filtering')
    local renderer = require('source.engine.graphics.pipeline.renderer').new(resources)
    renderer:resize(640, 360)
    assert(
        renderer.msaa == require('source.engine.graphics.quality.renderQuality').defaultSamples()
            and renderer.density >= 1,
        'Default preserves native density with hardware-aware AA'
    )
    if renderer.msaa > 0 and love.graphics.getSystemLimits().canvasmsaa >= 2 then
        assert(renderer.actualMSAA >= 2, 'Supported edge AA must reach the actual target')
    end
    local defaultSamples = renderer.actualMSAA
    renderer.msaa = 2
    renderer:resize(640, 360)
    if love.graphics.getSystemLimits().canvasmsaa >= 2 then
        assert(renderer.actualMSAA >= 2, 'Optional MSAA still works on supported Intel hardware')
    end
    print('DEFAULT MSAA', defaultSamples)
    print('QUALITY', renderer.actualMSAA, ui:font(22):getDPIScale(), image:getMipmapCount())
    renderer:release()
    ui:release()
    resources:release()
    print('QUALITY CHECK COMPLETE')
    love.event.quit()
end
return Tests
