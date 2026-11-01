-- Fixtures: shapes attached to bodies with material and collision filtering.

local ffi = require('ffi')
local Binding = require('source.katsa.physics.binding')
local Scale = require('source.katsa.physics.scale')
local Registry = require('source.katsa.physics.registry')
local Object = require('source.katsa.physics.object')
local Shape = require('source.katsa.physics.shape')
local B = Binding.lib
local up = Scale.up
local down = Scale.down
local quad = Binding.quad
local six = Binding.six
local alive = Object.alive

local M = {}
local Fixture = Object.class('Fixture')

function M.newFixture(body, shape, density)
    alive(body, 'Body')
    local handle = B().kb2_fixture_new(body._h, shape._h, density or 1)
    local self = setmetatable({ _h = handle, _body = body }, Fixture)
    self._id = Registry.register(self)
    B().kb2_fixture_set_userid(handle, self._id)
    body._fixtures[self] = true
    return self
end

function Fixture:getBody()
    return self._body
end

function Fixture:getShape()
    alive(self, 'Fixture')
    self._shape = self._shape or Shape.wrap(B().kb2_fixture_shape(self._h))
    return self._shape
end

function Fixture:getType()
    return self:getShape():getType()
end

function Fixture:getFriction()
    return B().kb2_fixture_get(self._h, 0)
end

function Fixture:setFriction(v)
    alive(self, 'Fixture')
    B().kb2_fixture_set(self._h, 0, v)
end

function Fixture:getRestitution()
    return B().kb2_fixture_get(self._h, 1)
end

function Fixture:setRestitution(v)
    B().kb2_fixture_set(self._h, 1, v)
end

function Fixture:getDensity()
    return B().kb2_fixture_get(self._h, 2)
end

function Fixture:setDensity(v)
    B().kb2_fixture_set(self._h, 2, v)
end

function Fixture:isSensor()
    alive(self, 'Fixture')
    return B().kb2_fixture_get(self._h, 3) ~= 0
end

function Fixture:setSensor(v)
    B().kb2_fixture_set(self._h, 3, v and 1 or 0)
end

function Fixture:getFilterData()
    local out = ffi.new('int[3]')
    B().kb2_fixture_get_filter(self._h, out)
    return out[0], out[1], out[2]
end

function Fixture:setFilterData(category, mask, group)
    B().kb2_fixture_set_filter(self._h, category, mask, group)
end

function Fixture:getCategory()
    local c, _ = self:getFilterData()
    local list = {}
    for i = 1, 16 do
        if bit.band(c, bit.lshift(1, i - 1)) ~= 0 then
            list[#list + 1] = i
        end
    end
    return unpack(list)
end

function Fixture:getGroupIndex()
    local _, _, g = self:getFilterData()
    return g
end

function Fixture:setGroupIndex(g)
    local c, m = self:getFilterData()
    B().kb2_fixture_set_filter(self._h, c, m, g)
end

function Fixture:setUserData(data)
    self._userdata = data
end

function Fixture:getUserData()
    return self._userdata
end

function Fixture:testPoint(x, y)
    return B().kb2_fixture_test_point(self._h, down(x), down(y)) ~= 0
end

function Fixture:rayCast(x1, y1, x2, y2, maxFraction, child)
    local index = (child or 1) - 1
    local hit = B().kb2_fixture_raycast(self._h, down(x1), down(y1), down(x2), down(y2),
        maxFraction, index, six)
    if hit == 0 then
        return nil
    end
    return six[0], six[1], six[2]
end

function Fixture:getBoundingBox(child)
    B().kb2_fixture_aabb(self._h, (child or 1) - 1, quad)
    return up(quad[0]), up(quad[1]), up(quad[2]), up(quad[3])
end

function Fixture:getMassData()
    B().kb2_fixture_mass(self._h, quad)
    return up(quad[0]), up(quad[1]), quad[2], up(up(quad[3]))
end

function Fixture:isDestroyed()
    return self._destroyed == true
end

function Fixture:destroy()
    if self._destroyed then
        return false
    end
    B().kb2_fixture_destroy(self._body._h, self._h)
    self._destroyed = true
    self._body._fixtures[self] = nil
    Registry.unregister(self._id)
    return true
end

M.class = Fixture

return M
