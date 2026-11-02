local ipairs = require('../math.array').ipairs
-- Install one cohesive responsibility on the public class.
local Validation = require('./validation')
local modes, unit = Validation.modes, Validation.unit
local Spatial = {}

function Spatial.install(Audio)
    function Audio:apply(v)
        if v.released then
            return
        end
        unit(v.volume, 'Voice volume')
        assert(type(v.pitch) == 'number' and v.pitch > 0 and v.pitch <= 8, 'Invalid voice pitch')
        assert(
            modes[v.rolloff]
                and v.minDistance >= 0
                and v.maxDistance > v.minDistance
                and v.maxDistance < math.huge
                and v.stereoWidth >= 0,
            'Invalid voice distance, rolloff or stereo width'
        )
        local attenuation = 1
        if v.spatial then
            local p = v.object and v.object.position or v.position
            if v.object and v.object.getWorldPosition then
                v._worldPosition = v._worldPosition or {}
                p = v.object:getWorldPosition(v._worldPosition)
            end
            local l = self.listener
            local distance = math.sqrt((p[1] - l[1]) ^ 2 + (p[2] - l[2]) ^ 2 + (p[3] - l[3]) ^ 2)
            local t = math.max(
                0,
                math.min(1, (distance - v.minDistance) / (v.maxDistance - v.minDistance))
            )
            if distance >= v.maxDistance then
                attenuation = 0
            elseif v.rolloff == 'Linear' then
                attenuation = 1 - t
            elseif v.rolloff == 'LinearSquare' then
                attenuation = (1 - t) ^ 2
            else
                attenuation = math.max(v.minDistance, 0.001)
                    / math.max(distance, v.minDistance, 0.001)
            end
            for i, source in ipairs(v.sources) do
                local offset = #v.sources == 2 and (i == 1 and -0.5 or 0.5) * v.stereoWidth or 0
                local ox, oy, oz = offset, 0, 0
                if
                    v.object
                    and (v.object.getEmitterMatrix or v.object.getWorldMatrix)
                    and offset ~= 0
                then
                    local matrix = (v.object.getEmitterMatrix or v.object.getWorldMatrix)(v.object)
                    local length = math.sqrt(matrix[1] ^ 2 + matrix[5] ^ 2 + matrix[9] ^ 2)
                    if length > 0 then
                        ox, oy, oz =
                            matrix[1] * offset / length,
                            matrix[5] * offset / length,
                            matrix[9] * offset / length
                    end
                end
                source:setPosition(p[1] + ox, p[2] + oy, -p[3] - oz)
            end
        end
        v.gain = v.volume * self:groupGain(v.group) * attenuation
        local scale = v.timeScaled and self.clock and self.clock.scale or 1
        if v.timeScaled and self.worldRoot then
            scale = scale * self.worldRoot.timeScale
        end
        local frozen = scale == 0
        if frozen and not v.timePaused then
            v.timeWasPlaying = v:isPlaying()
            for _, source in ipairs(v.sources) do
                source:pause()
            end
        elseif
            not frozen
            and v.timePaused
            and v.timeWasPlaying
            and not self.paused
            and not v.manualPause
        then
            for _, source in ipairs(v.sources) do
                source:play()
            end
        end
        v.timePaused = frozen
        for _, source in ipairs(v.sources) do
            source:setVolume(v.gain)
            source:setPitch(math.max(0.01, math.min(8, v.pitch * math.max(scale, 0.01))))
        end
    end
end

return Spatial
