local unpack = require('source.engine.math.array').unpack

local P = {}

function P.copy(v)
    return { unpack(v) }
end

function P.normalize(q)
    local l = math.sqrt(q[1] ^ 2 + q[2] ^ 2 + q[3] ^ 2 + q[4] ^ 2)
    assert(l > 1e-10, 'Animation contains a zero quaternion')
    for i = 1, 4 do
        q[i] = q[i] / l
    end
    return q
end

function P.slerp(a, b, t, out)
    out = out or {}
    local dot = 0
    for i = 1, 4 do
        dot = dot + a[i] * b[i]
    end
    local sign = dot < 0 and -1 or 1
    dot = math.min(1, math.abs(dot))
    local wa, wb = 1 - t, t
    if dot < 0.9995 then
        local angle = math.acos(dot)
        local s = math.sin(angle)
        wa, wb = math.sin((1 - t) * angle) / s, math.sin(t * angle) / s
    end
    for i = 1, 4 do
        out[i] = a[i] * wa + b[i] * wb * sign
    end
    return P.normalize(out)
end

function P.sample(channel, time, out)
    out = out or {}
    local times = channel.times
    local a, b = 1, #times
    if time <= times[1][1] then
        b = 1
    elseif time >= times[b][1] then
        a = b
    else
        -- A numeric interval hint never owns clips or tracks. Verify both live
        -- endpoints on every call; seeks, shared channels and key edits fall back.
        local interval = channel._sampleInterval
        if
            interval
            and interval < b
            and times[interval]
            and times[interval][1] <= time
            and time < times[interval + 1][1]
        then
            a, b = interval, interval + 1
        end
        while b - a > 1 do
            local mid = math.floor((a + b) / 2)
            if times[mid][1] <= time then
                a = mid
            else
                b = mid
            end
        end
    end
    channel._sampleInterval = a
    local duration = times[b][1] - times[a][1]
    local t = a == b and 0 or math.max(0, math.min(1, (time - times[a][1]) / duration))
    local values = channel.values
    if channel.method == 'CUBICSPLINE' then
        local va, vb = values[(a - 1) * 3 + 2], values[(b - 1) * 3 + 2]
        local ta, tb = values[(a - 1) * 3 + 3], values[(b - 1) * 3 + 1]
        local t2, t3 = t * t, t * t * t
        for i = 1, #va do
            out[i] = (2 * t3 - 3 * t2 + 1) * va[i]
                + (t3 - 2 * t2 + t) * duration * ta[i]
                + (-2 * t3 + 3 * t2) * vb[i]
                + (t3 - t2) * duration * tb[i]
        end
        if channel.target == 'rotation' then
            P.normalize(out)
        end
    elseif channel.target == 'rotation' and channel.method ~= 'STEP' then
        P.slerp(values[a], values[b], t, out)
    else
        if channel.method == 'STEP' then
            t = 0
        end
        for i = 1, #values[a] do
            out[i] = values[a][i] + (values[b][i] - values[a][i]) * t
        end
    end
    return out
end

return P
