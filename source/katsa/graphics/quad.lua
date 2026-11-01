-- Quad objects (sub-rectangles of a texture).

local State = require('source.katsa.graphics.state')
local G = State.G
local M = {}

local QuadMethods = {}
QuadMethods.__index = QuadMethods
function G.newQuad(x, y, w, h, sw, sh)
    if type(sw) == 'table' then
        sw, sh = sw:getPixelDimensions()
    end
    return setmetatable({ x = x, y = y, w = w, h = h, sw = sw, sh = sh }, QuadMethods)
end

function QuadMethods:getViewport()
    return
    self.x, self.y, self.w, self.h
end

function QuadMethods:setViewport(x, y, w, h, sw, sh)
    self.x, self.y, self.w, self.h = x, y, w, h
    if sw then
        self.sw, self.sh = sw, sh
    end
end

function QuadMethods:getTextureDimensions()
    return
    self.sw, self.sh
end

function QuadMethods:type()
    return 'Quad'
end

function QuadMethods:typeOf(name)
    return name == 'Quad' or name == 'Object'
end

function QuadMethods:release()
    return true
end

M.QuadMethods = QuadMethods

return M
