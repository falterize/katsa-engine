-- Smooth drawing of bodies this process simulates itself.
--
-- The physics world steps at a fixed rate while frames come at any rate (or, with a TimeScale,
-- many steps in one frame). A model written by the simulation therefore changes in jumps, and a
-- camera following it stutters. RenderPose keeps the last two simulated poses of a model and
-- blends them with the physics interpolation alpha; views and the camera read the blended
-- `r*` fields (rx, ry, rz, rheading, rpitch, rroll) and fall back to the raw model otherwise.
local RenderPose = {}

local POSITION = { 'x', 'y', 'z' }
local ANGLES = { 'heading', 'pitch', 'roll' }
local TELEPORT = 4 -- meters: a bigger jump between two samples is a respawn, not motion

local function copy(model, into)
    for _, key in ipairs(POSITION) do
        into[key] = model[key] or 0
    end
    for _, key in ipairs(ANGLES) do
        into[key] = model[key] or 0
    end
end

local function angle(a, b, t)
    return (a + ((b - a + 180) % 360 - 180) * t) % 360
end

-- Call once per frame after the physics update, for a model the simulation writes.
function RenderPose.sample(model)
    local pose = model._renderPose
    if not pose then
        pose = { prev = {}, cur = {} }
        copy(model, pose.cur)
        copy(model, pose.prev)
        model._renderPose = pose
        return
    end
    local cur = pose.cur
    local changed = false
    for _, key in ipairs(POSITION) do
        changed = changed or (model[key] or 0) ~= cur[key]
    end
    for _, key in ipairs(ANGLES) do
        changed = changed or (model[key] or 0) ~= cur[key]
    end
    if changed then
        pose.prev, pose.cur = pose.cur, pose.prev
        copy(model, pose.cur)
        local dx, dy, dz =
            pose.cur.x - pose.prev.x, pose.cur.y - pose.prev.y, pose.cur.z - pose.prev.z
        if dx * dx + dy * dy + dz * dz > TELEPORT * TELEPORT then
            copy(model, pose.prev)
        end
    end
end

-- Writes the blended pose for `alpha` (0..1) into the r* fields.
function RenderPose.apply(model, alpha)
    local pose = model._renderPose
    if not pose then
        return
    end
    local a, b = pose.prev, pose.cur
    alpha = math.max(0, math.min(1, alpha or 1))
    model.rx = a.x + (b.x - a.x) * alpha
    model.ry = a.y + (b.y - a.y) * alpha
    model.rz = a.z + (b.z - a.z) * alpha
    model.rheading = angle(a.heading, b.heading, alpha)
    model.rpitch = angle(a.pitch, b.pitch, alpha)
    model.rroll = angle(a.roll, b.roll, alpha)
end

-- The model is no longer simulated here (a network interpolator drives it): draw it raw.
function RenderPose.clear(model)
    model._renderPose = nil
    model.rx, model.ry, model.rz = nil, nil, nil
    model.rheading, model.rpitch, model.rroll = nil, nil, nil
end

return RenderPose
