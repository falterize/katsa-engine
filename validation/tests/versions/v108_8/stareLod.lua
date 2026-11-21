-- stareShooter demo: two rows of LODGroups (hard and cross-faded switch) with one slider for the
-- maximum distance, and a Datamosh screen shader that is off until it is switched on.
local Application = require('source.runtime.application')

local Module = {}

-- Draws vertical stripes under the interface (stand-in for the 3D render) and returns the pixels.
local function render(scene)
    local g = katsa.graphics
    local w, h = g.getDimensions()
    local canvas = g.newCanvas(w, h, { dpiscale = 1 })
    g.push('all')
    g.setCanvas({ canvas, stencil = true })
    g.clear(0, 0, 0, 1)
    for x = 0, w, 16 do
        g.setColor(x % 32 == 0 and 1 or 0.1, 0.5, x % 32 == 0 and 0.1 or 1, 1)
        g.rectangle('fill', x, 0, 16, h)
    end
    g.setColor(1, 1, 1, 1)
    local ui = scene.root:find('World3D/World2D')
    ui:fit(w, h)
    ui:draw()
    g.pop()
    local data = canvas:newImageData()
    canvas:release()
    return data, w, h
end

local function differing(a, b, w, h)
    local count = 0
    for y = 0, h - 1, 8 do
        for x = 0, w - 1, 8 do
            local r1, g1, b1 = a:getPixel(x, y)
            local r2, g2, b2 = b:getPixel(x, y)
            if math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2) > 0.2 then
                count = count + 1
            end
        end
    end
    return count
end

function Module.run(self)
    local scene = Application.new(self.manager, 'stareShooter')
    scene:load()
    local demo = scene.demo.lod
    local hard, fade = 0, 0
    for _, group in ipairs(demo.groups) do
        hard = hard + (group.fadeTime == 0 and 1 or 0)
        fade = fade + (group.fadeTime > 0 and 1 or 0)
        assert(group.billboardImage ~= '', 'every demo tree ends in a billboard')
    end
    self:check(hard == 7 and fade == 7, 'The demo has a row with a hard switch and a row with a fade')
    demo:setReach(40)
    local first = demo.groups[1]
    self:check(
        first.distances:find('^6.8, 14.8, 25.6, 40.0') ~= nil,
        'The max distance slider value moves every switch point of every tree'
    )
    local ui = scene.root:find('World3D/World2D')
    local slider = ui:find('LodControls/Slider') or ui.content:find('LodControls'):find('Slider')
    self:check(slider ~= nil, 'The LOD panel has the max distance slider')

    local effect = ui.content:find('Datamosh')
    self:check(
        effect and effect.enabled == false and not scene.settings.datamosh.enabled,
        'The Datamosh shader exists and is off by default'
    )
    for _, node in ipairs(ui.content.children) do
        if node ~= effect then
            node.visible = false
        end
    end
    effect.enabled = true
    render(scene)
    self:check(effect.enabled and render(scene) ~= nil, 'Switching Datamosh on renders without errors')
    scene.input.keyHandler('f8')
    local pinned = effect.uniforms.pin
    scene.input.keyHandler('f8')
    self:check(pinned == 1 and effect.uniforms.pin == 0, 'F8 pins the frame for the Datamosh and releases it')
    render(scene)
    scene:release()
end

return Module
