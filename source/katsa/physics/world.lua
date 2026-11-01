-- World: stepping, callbacks, queries and ownership of bodies and joints.

local ffi = require('ffi')
local Binding = require('source.katsa.physics.binding')
local Scale = require('source.katsa.physics.scale')
local Registry = require('source.katsa.physics.registry')
local Errors = require('source.katsa.physics.errors')
local Object = require('source.katsa.physics.object')
local Contact = require('source.katsa.physics.contact')
local B, up, down, pair, alive = Binding.lib, Scale.up, Scale.down, Binding.pair, Object.alive

local M = {}
local World = Object.class('World')
local trampolines

local function installTrampolines()
    if trampolines then
        return trampolines
    end
    local t = {}
    local function contactEvent(name)
        return ffi.cast('kb2_contact_cb', Errors.guard(function(user, contactHandle)
            local world = Registry.get(user)
            local callback = world and world._callbacks[name]
            if callback then
                local contact = Contact.wrap(contactHandle)
                local a, b = contact:getFixtures()
                callback(a, b, contact)
            end
        end))
    end
    t.begin, t.finish, t.pre = contactEvent('begin'), contactEvent('end'), contactEvent('pre')
    t.post = ffi.cast('kb2_post_cb', Errors.guard(function(user, contactHandle, impulses, count)
        local world = Registry.get(user)
        local callback = world and world._callbacks.post
        if callback then
            local contact = Contact.wrap(contactHandle)
            local a, b = contact:getFixtures()
            local n1, t1, n2, t2 = up(impulses[0]), up(impulses[1]), nil, nil
            if count > 1 then
                n2, t2 = up(impulses[2]), up(impulses[3])
            end
            callback(a, b, contact, n1, t1, n2, t2)
        end
    end))
    t.filter = ffi.cast('kb2_filter_cb', Errors.guard(function(user, ha, hb)
        local world = Registry.get(user)
        local filter = world and world._filter
        if not filter then
            return 1
        end
        return filter(Registry.fixtureOf(ha), Registry.fixtureOf(hb)) and 1 or 0
    end))
    trampolines = t
    return t
end

function M.newWorld(gx, gy, sleep)
    local world = setmetatable({ _bodies = {}, _joints = {}, _callbacks = {} }, World)
    world._id = Registry.register(world)
    local handle = B().kb2_world_new(down(gx or 0), down(gy or 0), world._id)
    world._h = ffi.gc(handle, B().kb2_world_free)
    B().kb2_world_set_sleeping_allowed(world._h, sleep ~= false and 1 or 0)
    return world
end

function World:update(dt, velocityIterations, positionIterations)
    alive(self, 'World')
    installTrampolines()
    B().kb2_world_step(self._h, dt, velocityIterations or 8, positionIterations or 3)
    Errors.rethrow()
end

function World:setGravity(x, y)
    alive(self, 'World')
    B().kb2_world_set_gravity(self._h, down(x), down(y))
end

function World:getGravity()
    alive(self, 'World')
    B().kb2_world_get_gravity(self._h, pair)
    return up(pair[0]), up(pair[1])
end

function World:setCallbacks(begin, finish, pre, post)
    alive(self, 'World')
    local t = installTrampolines()
    self._callbacks = { begin = begin, ['end'] = finish, pre = pre, post = post }
    B().kb2_world_set_callbacks(self._h, begin and t.begin or nil, finish and t.finish or nil,
        pre and t.pre or nil, post and t.post or nil)
end

function World:getCallbacks()
    local c = self._callbacks
    return c.begin, c['end'], c.pre, c.post
end

function World:setContactFilter(fn)
    alive(self, 'World')
    local t = installTrampolines()
    self._filter = fn
    B().kb2_world_set_filter(self._h, fn and t.filter or nil)
end

function World:getContactFilter()
    return self._filter
end

function World:isLocked()
    return B().kb2_world_is_locked(self._h) ~= 0
end

function World:isSleepingAllowed()
    return B().kb2_world_get_sleeping_allowed(self._h) ~= 0
end

function World:setSleepingAllowed(v)
    B().kb2_world_set_sleeping_allowed(self._h, v and 1 or 0)
end

function World:getBodies()
    return Object.sortedKeys(self._bodies)
end

function World:getBodyCount()
    return Object.count(self._bodies)
end

function World:getJoints()
    return Object.sortedKeys(self._joints)
end

function World:getJointCount()
    return Object.count(self._joints)
end

function World:getContactCount()
    return B().kb2_world_contact_count(self._h)
end

function World:getContacts()
    local handles = ffi.new('void*[?]', math.max(self:getContactCount(), 1))
    local n = B().kb2_world_contacts(self._h, handles, self:getContactCount())
    local out = {}
    for i = 0, n - 1 do
        out[#out + 1] = Contact.wrap(handles[i])
    end
    return out
end

function World:translateOrigin(x, y)
    B().kb2_world_shift_origin(self._h, down(x), down(y))
end

local queryStack = {}
local queryCallback, rayCallback
function World:queryBoundingBox(x1, y1, x2, y2, callback)
    alive(self, 'World')
    queryCallback = queryCallback or ffi.cast('kb2_query_cb', Errors.guard(function(handle)
        local current = queryStack[#queryStack]
        return current(Registry.fixtureOf(handle)) and 1 or 0
    end))
    queryStack[#queryStack + 1] = callback
    local lx, ly, ux, uy = math.min(x1, x2), math.min(y1, y2), math.max(x1, x2), math.max(y1, y2)
    B().kb2_world_query(self._h, down(lx), down(ly), down(ux), down(uy), queryCallback)
    queryStack[#queryStack] = nil
    Errors.rethrow()
end

function World:rayCast(x1, y1, x2, y2, callback)
    alive(self, 'World')
    rayCallback = rayCallback or ffi.cast('kb2_ray_cb', Errors.guard(function(handle, x, y, nx, ny,
        fraction)
        local current = queryStack[#queryStack]
        return current(Registry.fixtureOf(handle), up(x), up(y), nx, ny, fraction) or 0
    end))
    queryStack[#queryStack + 1] = callback
    B().kb2_world_raycast(self._h, down(x1), down(y1), down(x2), down(y2), rayCallback)
    queryStack[#queryStack] = nil
    Errors.rethrow()
end

function World:isDestroyed()
    return self._destroyed == true
end

function World:destroy()
    if self._destroyed then
        return false
    end
    for body in pairs(self._bodies) do
        body._destroyed = true
        Registry.unregister(body._id)
        for fixture in pairs(body._fixtures) do
            fixture._destroyed = true
            Registry.unregister(fixture._id)
        end
    end
    for joint in pairs(self._joints) do
        joint._destroyed = true
        Registry.unregister(joint._id)
    end
    self._bodies, self._joints = {}, {}
    ffi.gc(self._h, nil)
    B().kb2_world_free(self._h)
    self._destroyed = true
    Registry.unregister(self._id)
    return true
end

function World:typeOf(name)
    return name == 'World' or name == 'Object'
end

M.class = World

return M
