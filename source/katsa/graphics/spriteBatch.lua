-- Sprite batches.

local State = require('source.katsa.graphics.state')
local Batch = require('source.katsa.graphics.batch')
local Color = require('source.katsa.graphics.color')
local Draw = require('source.katsa.graphics.draw')
local Quad = require('source.katsa.graphics.quad')
local S = State.S
local G = State.G

local SpriteBatch = {}
SpriteBatch.__index = SpriteBatch
function G.newSpriteBatch(texture, size, usage)
    return setmetatable({ _texture = texture, _entries = {}, _color = nil }, SpriteBatch)
end

function SpriteBatch:add(...)
    local args = { ... }
    local quad
    if type(args[1]) == 'table' and getmetatable(args[1]) == Quad.QuadMethods then
        quad = table.remove(args, 1)
    end
    local entry = { quad = quad, args = args, color = self._color and { unpack(self._color) } }
    self._entries[#self._entries + 1] = entry
    return #self._entries
end

function SpriteBatch:set(id, ...)
    local args = { ... }
    local quad
    if type(args[1]) == 'table' and getmetatable(args[1]) == Quad.QuadMethods then
        quad = table.remove(args, 1)
    end
    local color = self._color and { unpack(self._color) }
    self._entries[id] = { quad = quad, args = args, color = color }
end

function SpriteBatch:clear()
    self._entries = {}
end

function SpriteBatch:flush() end
function SpriteBatch:setTexture(texture)
    self._texture = texture
end

function SpriteBatch:getTexture()
    return self._texture
end

function SpriteBatch:setColor(r, g, b, a)
    if r == nil then
        self._color = nil
    else
        r, g, b, a = Color.colorArgs(r, g, b, a)
        self._color = { r, g, b, a }
    end
end

function SpriteBatch:getCount()
    return #self._entries
end

function SpriteBatch:_draw2D(graphics, matrix)
    local saved = { unpack(S.color) }
    local savedTransform = { unpack(S.transform) }
    for i = 1, 6 do
        S.transform[i] = matrix[i]
    end
    for _, entry in ipairs(self._entries) do
        if entry.color then
            G.setColor(entry.color)
        else
            G.setColor(saved)
        end
        local a = entry.args
        local m = Batch.composed(a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9])
        Draw.drawTexture(self._texture, entry.quad, m)
    end
    for i = 1, 6 do
        S.transform[i] = savedTransform[i]
    end
    G.setColor(saved)
end

function SpriteBatch:release()
    return true
end

function SpriteBatch:type()
    return 'SpriteBatch'
end

function SpriteBatch:typeOf(name)
    return name == 'SpriteBatch' or name == 'Drawable' or name == 'Object'
end
