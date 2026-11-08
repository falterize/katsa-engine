-- Diagnostic: is the windowsLab frame transparent where nothing is drawn, and does a UI text that
-- changes every frame change that? The frame is drawn into an RGBA canvas and its alpha is read.
-- Run: xvfb-run -a luajit tools/dev/katsa.lua . --test-v108.7.alpha
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.frame = 0
    return self
end

function Tests:update() end

local function alphaAt(canvas)
    local data = canvas:newImageData()
    local w, h = data:getWidth(), data:getHeight()
    local out = {}
    for _, p in ipairs({ { 4, h - 4 }, { w - 4, h - 4 }, { w - 4, h / 2 }, { w / 2, h - 60 }, { w / 2, 4 } }) do
        local _, _, _, a = data:getPixel(math.floor(p[1]), math.floor(p[2]))
        out[#out + 1] = string.format('%.2f', a)
    end
    return table.concat(out, ' ')
end

function Tests:draw()
    self.frame = self.frame + 1
    local frame = self.frame
    if frame == 1 then
        self.host = require('source.game.runtime.application').new(self.manager, 'windowsLab')
        self.host:load()
        self.canvas = katsa.graphics.newCanvas(katsa.graphics.getWidth(), katsa.graphics.getHeight())
        return
    end
    local lab = self.host.instance or self.host.demo
    local g = katsa.graphics
    local function render(changing)
        if changing and self.host.demo and self.host.demo.status then
            self.host.demo.status.text = 'frame ' .. frame
        end
        self.host:update(1 / 60, 1 / 60)
        g.setCanvas(self.canvas)
        self.host:draw()
        g.setCanvas()
    end
    if frame == 10 then
        render(false)
        print('ALPHA static  corner', alphaAt(self.canvas))
    elseif frame == 20 then
        render(true)
        render(true)
        print('ALPHA changing corner', alphaAt(self.canvas))
        katsa.event.quit()
    else
        self.host:update(1 / 60, 1 / 60)
        self.host:draw()
    end
end

return Tests
