-- Retargeting: re-expresses an animation clip authored for one skeleton on another.
--
-- Bones are matched by name (case, punctuation and namespace prefixes such as `mixamorig:` are
-- ignored; `boneMap` overrides pairs by hand). Each matched channel is converted from the
-- source bone's rest pose to the target bone's rest pose:
--
--   rotation:    target = (targetRest * sourceRest^-1) * sourceKey   (a constant left factor, so
--                cubic-spline tangents convert by the same factor)
--   translation: target = targetRest + (sourceKey - sourceRest) * ratio, where ratio is the
--                target bone length over the source bone length (1 when the source has none)
--   scale:       target = targetRest * sourceKey / sourceRest
--
-- This assumes both rigs share bone orientation conventions; bones without a counterpart are
-- skipped. The result is a new clip whose channels point at the target model's nodes.
local Retarget = {}

local MIN_MATCH = 0.5 -- a clip that keeps fewer of its channels than this is refused

-- "mixamorig:LeftArm", "Armature|Left_Arm" and "left arm" all become "leftarm".
function Retarget.normalize(name)
    return (tostring(name):gsub('^.*[:|]', ''):gsub('[^%w]', ''):lower())
end

local function multiply(a, b)
    return {
        a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2],
        a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
        a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4],
        a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3],
    }
end

local function inverse(q)
    local n = q[1] ^ 2 + q[2] ^ 2 + q[3] ^ 2 + q[4] ^ 2
    return { -q[1] / n, -q[2] / n, -q[3] / n, q[4] / n }
end

local function length(v)
    return math.sqrt(v[1] ^ 2 + v[2] ^ 2 + v[3] ^ 2)
end

-- Cubic-spline channels store {in tangent, value, out tangent} per key; tangents are not
-- positions, so offsets apply to the value entry only.
local function entryKind(channel, index)
    if channel.method ~= 'CUBICSPLINE' then
        return 'value'
    end
    return ((index - 1) % 3 == 1) and 'value' or 'tangent'
end

local function convert(channel, source, target, ratio)
    local values = {}
    local restS, restT = source.rest, target.rest
    if channel.target == 'rotation' then
        local factor = multiply(restT.rotation, inverse(restS.rotation))
        for i, value in ipairs(channel.values) do
            values[i] = multiply(factor, value)
        end
    elseif channel.target == 'translation' then
        for i, value in ipairs(channel.values) do
            local out = {}
            for k = 1, 3 do
                if entryKind(channel, i) == 'value' then
                    out[k] = restT.translation[k] + (value[k] - restS.translation[k]) * ratio
                else
                    out[k] = value[k] * ratio
                end
            end
            values[i] = out
        end
    else
        for i, value in ipairs(channel.values) do
            local out = {}
            for k = 1, 3 do
                local rest = restS.scale[k]
                local factor = math.abs(rest) > 1e-8 and restT.scale[k] / rest or 1
                out[k] = value[k] * factor
            end
            values[i] = out
        end
    end
    return {
        node = target,
        target = channel.target,
        method = channel.method,
        times = channel.times,
        values = values,
    }
end

local function index(model)
    local byName = {}
    for _, node in ipairs(model.nodes) do
        if node.name then
            byName[Retarget.normalize(node.name)] = node
        end
    end
    return byName
end

-- Returns a clip for `model` and the number of source channels that found a bone, or nil and a
-- message. `options.boneMap` maps source bone names to target bone names.
function Retarget.clip(clip, model, options)
    options = options or {}
    local byName = index(model)
    local mapped = {}
    for from, to in pairs(options.boneMap or {}) do
        mapped[Retarget.normalize(from)] = Retarget.normalize(to)
    end
    local result = {
        name = clip.name,
        duration = clip.duration,
        markers = clip.markers or {},
        order = clip.order,
        speed = clip.speed,
        fadeIn = clip.fadeIn,
        fadeOut = clip.fadeOut,
        channels = {},
        retargeted = true,
    }
    local kept, missing = 0, {}
    for _, channel in ipairs(clip.channels) do
        local source = channel.node
        local key = Retarget.normalize(source.name or '')
        local target = byName[mapped[key] or key]
        if target and target.rest and source.rest then
            local sourceLength = length(source.rest.translation)
            local targetLength = length(target.rest.translation)
            local ratio = sourceLength > 1e-8 and targetLength / sourceLength or 1
            result.channels[#result.channels + 1] = convert(channel, source, target, ratio)
            kept = kept + 1
        else
            missing[#missing + 1] = source.name or '?'
        end
    end
    local total = #clip.channels
    if total == 0 or kept / total < MIN_MATCH then
        return nil,
            ('only %d of %d channels of animation %s match bones of this model (%s); pass '
                .. 'settings.retarget = { boneMap = { SourceBone = "TargetBone" } }'):format(
                kept,
                total,
                tostring(clip.name),
                table.concat(missing, ', '):sub(1, 120)
            )
    end
    return result, kept
end

return Retarget
