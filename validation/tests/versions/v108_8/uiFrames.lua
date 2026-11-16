-- Interface drawing checked by pixels: logic tests pass on a tree that draws nothing, so the draw
-- path of a World2D (the scene's own and one a prefab copy brings) is read back from a canvas.
local Application = require('game.runtime.application')

local Module = {}

local FOLDER = 'validation/tests/fixtures/prefabs/crate'
local WIDTH, HEIGHT = 480, 320

-- Draws `ui` full-size into a fresh canvas and returns its pixels.
local function render(ui)
    local canvas = katsa.graphics.newCanvas(WIDTH, HEIGHT, { dpiscale = 1 })
    katsa.graphics.push('all')
    katsa.graphics.setCanvas({ canvas, stencil = true })
    katsa.graphics.origin()
    katsa.graphics.clear(0, 0, 0, 0, 0)
    ui.width, ui.height, ui.scale, ui.offsetX, ui.offsetY = WIDTH, HEIGHT, 1, 0, 0
    ui:draw()
    katsa.graphics.pop()
    return canvas:newImageData()
end

function Module.run(self)
    local scene = Application.new(self.manager, 'stareShooter')
    scene:load()
    local ui = scene.root:find('World3D/World2D')
    local box = ui:container({
        position = { 0, 100, 0, 100 },
        size = { 0, 40, 0, 40 },
        backgroundColor = { 1, 0, 0, 1 },
    }, ui.content)
    local pixels = render(ui)
    local r, g, b, a = pixels:getPixel(120, 120)
    local _, _, _, outside = pixels:getPixel(20, 20)
    self:check(
        r > 0.9 and g < 0.1 and b < 0.1 and a > 0.9 and outside == 0,
        'A World2D draws its widgets where they are laid out (red box inside, nothing outside)'
    )
    box:destroy()

    -- A prefab copy brings its own World2D; it must draw too (and only what the prefab put in it).
    local copy = scene.world.prefabs:instantiate(FOLDER, { name = 'Framed' })
    local own = copy:find('World2D')
    local _, _, _, button = render(own):getPixel(20, 10)
    local _, _, _, away = render(own):getPixel(400, 300)
    self:check(
        button > 0 and away == 0,
        'The World2D inside a prefab copy draws its own HUD (its button, not the whole screen)'
    )
    copy:destroy()
    scene:release()
end

return Module
