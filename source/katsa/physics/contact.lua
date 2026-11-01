-- Contacts: collision pairs reported to world callbacks and body queries.

local ffi = require('ffi')
local Binding = require('source.katsa.physics.binding')
local Scale = require('source.katsa.physics.scale')
local Registry = require('source.katsa.physics.registry')
local Object = require('source.katsa.physics.object')
local B, up, down, six = Binding.lib, Scale.up, Scale.down, Binding.six

local M = {}
local Contact = Object.class('Contact')
local cache = setmetatable({}, { __mode = 'v' })

function M.wrap(handle)
    local key = tonumber(ffi.cast('intptr_t', handle))
    local contact = cache[key]
    if not contact then
        contact = setmetatable({ _h = handle }, Contact)
        cache[key] = contact
    end
    return contact
end

function Contact:getPositions()
    local n = B().kb2_contact_world_manifold(self._h, six)
    local out = {}
    for i = 0, n - 1 do
        out[#out + 1], out[#out + 2] = up(six[2 + i * 2]), up(six[3 + i * 2])
    end
    return unpack(out)
end

function Contact:getNormal()
    B().kb2_contact_world_manifold(self._h, six)
    return six[0], six[1]
end

function Contact:getFixtures()
    local out = ffi.new('void*[2]')
    B().kb2_contact_fixtures(self._h, out)
    return Registry.fixtureOf(out[0]), Registry.fixtureOf(out[1])
end

function Contact:getChildren()
    return 1, 1
end

function Contact:isTouching()
    return B().kb2_contact_is_touching(self._h) ~= 0
end

function Contact:isEnabled()
    return B().kb2_contact_is_enabled(self._h) ~= 0
end

function Contact:setEnabled(v)
    B().kb2_contact_set_enabled(self._h, v and 1 or 0)
end

function Contact:getFriction()
    return B().kb2_contact_get(self._h, 0)
end

function Contact:setFriction(v)
    B().kb2_contact_set(self._h, 0, v)
end

function Contact:getRestitution()
    return B().kb2_contact_get(self._h, 1)
end

function Contact:setRestitution(v)
    B().kb2_contact_set(self._h, 1, v)
end

function Contact:getTangentSpeed()
    return up(B().kb2_contact_get(self._h, 2))
end

function Contact:setTangentSpeed(v)
    B().kb2_contact_set(self._h, 2, down(v))
end

function Contact:resetFriction()
    B().kb2_contact_reset(self._h, 0)
end

function Contact:resetRestitution()
    B().kb2_contact_reset(self._h, 1)
end

function Contact:isDestroyed()
    return false
end

M.class = Contact

return M
