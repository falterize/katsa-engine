-- Replicated on-foot player. The owning client simulates its own walker (Body3D + state machine)
-- and reports the pose; everybody else interpolates it. The server only relays and tracks it.
local WalkerEntity = {}

-- Index order is the wire format of the `state` field.
WalkerEntity.states = { 'idle', 'walk', 'run', 'jump', 'fall', 'crouch', 'drive', 'passenger' }

WalkerEntity.stateIndex = {}
for index, name in ipairs(WalkerEntity.states) do
    WalkerEntity.stateIndex[name] = index
end

function WalkerEntity.create(_, args)
    return {
        x = args.x or 0,
        y = args.y or 0,
        z = args.z or 0,
        heading = args.heading or 0,
        state = 1,
        speed = 0,
        walkBlend = 0,
        crouchBlend = 0,
        walkScale = 0,
        air = false,
        jumpSequence = 0,
        playerId = args.playerId,
        name = args.name or 'Player',
    }
end

local function get(walker, name)
    if name == 'position' then
        return { walker.x, walker.y, walker.z }
    end
    return walker[name]
end

local function set(walker, name, value)
    if name == 'position' then
        walker.x, walker.y, walker.z = value[1], value[2], value[3]
    else
        walker[name] = value
    end
end

WalkerEntity.definition = {
    create = WalkerEntity.create,
    get = get,
    set = set,
    clientAuthoritative = true,
    fields = {
        'position:vec3',
        'heading:angle',
        'state:u8',
        'speed:f32',
        'walkBlend:f32',
        'crouchBlend:f32',
        'walkScale:f32',
        'air:bool',
        'jumpSequence:u8',
    },
}

function WalkerEntity.define(target)
    local copy = {}
    for key, value in pairs(WalkerEntity.definition) do
        copy[key] = value
    end
    target:define('Walker', copy)
end

return WalkerEntity
