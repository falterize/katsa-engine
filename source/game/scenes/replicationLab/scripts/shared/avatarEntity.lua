local Arena = require('./arena')

-- The replicated pose of one player or bot. The owning client simulates its own character and
-- reports this pose; everybody else sees it interpolated. The server only checks it.
local AvatarEntity = {}

function AvatarEntity.create(_, args)
    return {
        x = args.x or 0,
        y = args.y or 1,
        z = args.z or 0,
        heading = 0,
        speed = 0,
        air = false,
        name = args.name or 'Player',
        bot = args.bot == true,
        -- Seconds during which the server accepts a jump of any length (after it moved the player).
        allowJump = 0,
    }
end

local function get(avatar, name)
    if name == 'position' then
        return { avatar.x, avatar.y, avatar.z }
    end
    return avatar[name]
end

local function set(avatar, name, value)
    if name == 'position' then
        avatar.x, avatar.y, avatar.z = value[1], value[2], value[3]
    else
        avatar[name] = value
    end
end

-- The server refuses a pose that is out of bounds or too far from the last one for the time passed.
local function validate(avatar, state, elapsed)
    local p = state.position
    if math.abs(p[1]) > Arena.limit or math.abs(p[3]) > Arena.limit or p[2] < -10 then
        return false, 'out of bounds'
    end
    if avatar.allowJump > 0 then
        return true
    end
    local dx, dz = p[1] - avatar.x, p[3] - avatar.z
    local reach = Arena.maxSpeed * math.max(elapsed, 0.05) + 1
    if dx * dx + dz * dz > reach * reach then
        return false, 'too fast'
    end
end

-- Both sides define the same fields; only `create` differs on the client (it does not need to).
function AvatarEntity.define(endpoint)
    endpoint:define('Avatar', {
        create = AvatarEntity.create,
        get = get,
        set = set,
        validate = validate,
        clientAuthoritative = true,
        fields = { 'position:vec3', 'heading:angle', 'speed:f32', 'air:bool' },
    })
end

return AvatarEntity
