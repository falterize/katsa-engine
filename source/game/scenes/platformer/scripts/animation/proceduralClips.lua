local ipairs = require('source.engine.math.array').ipairs

-- Authored demonstration motion, not animation data supplied by Mixamo.
local P = {}

local function rotate(q, x, y, z)
    local a, b, c = math.sin(x / 2), math.sin(y / 2), math.sin(z / 2)
    local ca, cb, cc = math.cos(x / 2), math.cos(y / 2), math.cos(z / 2)
    local v = {
        a * cb * cc - ca * b * c,
        ca * b * cc + a * cb * c,
        ca * cb * c - a * b * cc,
        ca * cb * cc + a * b * c,
    }
    return {
        q[4] * v[1] + q[1] * v[4] + q[2] * v[3] - q[3] * v[2],
        q[4] * v[2] - q[1] * v[3] + q[2] * v[4] + q[3] * v[1],
        q[4] * v[3] + q[1] * v[2] - q[2] * v[1] + q[3] * v[4],
        q[4] * v[4] - q[1] * v[1] - q[2] * v[2] - q[3] * v[3],
    }
end

function P.add(model)
    for _, state in ipairs({ 'Idle', 'Walk', 'Run', 'Jump', 'Fall', 'Wave' }) do
        local clip = {
            name = 'Demo ' .. state,
            duration = state == 'Run' and 0.6 or 1.2,
            channels = {},
            markers = {},
        }
        if state == 'Walk' or state == 'Run' then
            clip.markers = {
                { time = clip.duration * 0.25, name = 'Footstep', value = 'Left' },
                { time = clip.duration * 0.75, name = 'Footstep', value = 'Right' },
            }
        end
        for _, node in ipairs(model.nodes) do
            if node.isBone then
                local values, times = {}, {}
                for k = 0, 8 do
                    local phase = k / 8 * math.pi * 2
                    local side = node.name:find('Left') and 1 or -1
                    local x, y, z = 0, 0, 0
                    if node.name:find('Arm') and not node.name:find('ForeArm') then
                        z = side * 0.85
                        if state == 'Wave' and side == 1 then
                            z = -0.5
                            x = 0.8 + 0.35 * math.sin(phase)
                        end
                    end
                    if state == 'Walk' or state == 'Run' then
                        if node.name:find('UpLeg') then
                            x = side * math.sin(phase) * (state == 'Run' and 0.8 or 0.45)
                        end
                        if node.name:find('ForeArm') then
                            x = -0.35 + side * 0.2 * math.sin(phase)
                        end
                        if node.name:find('Leg') and not node.name:find('UpLeg') then
                            x = math.max(0, -side * math.sin(phase)) * 0.4
                        end
                    elseif state == 'Jump' and node.name:find('UpLeg') then
                        x = -0.45
                    elseif state == 'Fall' and node.name:find('Arm') then
                        x = 0.4
                        z = side * 0.4
                    end
                    if node.name:find('Spine') then
                        y = 0.035 * math.sin(phase)
                    end
                    times[#times + 1] = { k / 8 * clip.duration }
                    values[#values + 1] = rotate(node.rest.rotation, x, y, z)
                end
                clip.channels[#clip.channels + 1] = {
                    node = node,
                    target = 'rotation',
                    times = times,
                    values = values,
                    method = 'LINEAR',
                }
            end
        end
        model.animations[#model.animations + 1] = clip
    end
end

return P
