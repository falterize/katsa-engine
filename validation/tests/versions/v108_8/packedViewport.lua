-- A prefab copy inside the World3D of a ViewportFrame: its World2D is the interface of that
-- viewport (drawn into it and clickable there), not of the outer world.
local Application = require('source.runtime.application')

local Module = {}

local FOLDER = 'validation/tests/fixtures/prefabs/crate'

function Module.run(self)
    local scene = Application.new(self.manager, 'stareShooter')
    scene:load()
    local outer = scene.world
    local ui = scene.root:find('World3D/World2D')
    local frame = ui:create('ViewportFrame', {
        position = { 0, 10, 0, 10 },
        size = { 0, 300, 0, 160 },
    }, ui.content)
    local root = ui:create('World3D', { name = 'Inner' }, frame)
    local inner = root._world
    local before = #outer.uis
    local copy = inner.prefabs:instantiate(FOLDER, { name = 'InViewport' })
    local own = copy:find('World2D')
    local listed = false
    for _, item in ipairs(inner.uis) do
        listed = listed or item == own
    end
    self:check(
        own and listed and #outer.uis == before,
        'A prefab World2D inside a ViewportFrame belongs to the viewport World3D, not to the outer one'
    )
    local button = own.content:find('CrateButton')
    local presses = 0
    button:connect('press', function()
        presses = presses + 1
    end)
    local canvas = katsa.graphics.newCanvas(480, 320, { dpiscale = 1 })
    katsa.graphics.push('all')
    katsa.graphics.setCanvas({ canvas, stencil = true })
    katsa.graphics.origin()
    katsa.graphics.clear(0, 0, 0, 0, 0)
    ui:draw()
    katsa.graphics.pop()
    local pixel = inner.overlayCanvas:newImageData()
    local _, _, _, alpha = pixel:getPixel(20, 10)
    self:check(alpha > 0, 'The prefab interface is drawn into the viewport overlay')
    ui:pointer(frame, 'press', 10 + 20, 10 + 10, 'p')
    ui:pointer(frame, 'release', 10 + 20, 10 + 10, 'p')
    self:check(presses == 1, 'A click inside the viewport reaches the prefab interface')
    scene:release()
end

return Module
