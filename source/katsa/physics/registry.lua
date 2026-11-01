-- Maps Box2D user ids back to Lua objects. Strong references keep objects alive while they exist in
-- the native world; the weak table serves lookups from native callbacks.
local Binding = require('source.katsa.physics.binding')

local nextId = 1
local weak = setmetatable({}, { __mode = 'v' })
local strong = {}

local Registry = {}

function Registry.register(object)
    local id = nextId
    nextId = nextId + 1
    weak[id] = object
    strong[id] = object
    return id
end

function Registry.unregister(id)
    strong[id] = nil
    weak[id] = nil
end

function Registry.get(id)
    return weak[tonumber(id)]
end

function Registry.fixtureOf(handle)
    return weak[tonumber(Binding.lib().kb2_fixture_get_userid(handle))]
end

return Registry
