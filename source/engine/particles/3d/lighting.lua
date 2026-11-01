local unpack = require('source.engine.math.array').unpack
local ipairs = require('source.engine.math.array').ipairs
local M = require('source.engine.math.math3d')

local L = {}

function L.bind(shader, world, camera, emitter)
    local function send(name, ...)
        if shader:hasUniform(name) then
            shader:send(name, ...)
        end
    end
    local enabled = not emitter.unlit
        and (not emitter._systemEffects or emitter._systemEffects.lighting ~= false)
    send('particleUnlit', not enabled)
    send('particleBrightness', emitter.brightness)
    local ambient = world.environment.ambient
    send(
        'particleLighting',
        enabled and { ambient[1] / 255, ambient[2] / 255, ambient[3] / 255 } or { 1, 1, 1 }
    )
    send('particleWorldBrightness', world.environment.brightness)
    send('particleFacing', { -camera.forward[1], -camera.forward[2], -camera.forward[3] })
    local renderer = world._activeRenderer
    if renderer then
        renderer.shadows:send(shader, world.environment)
    end
    send(
        'receiveShadow',
        enabled and emitter.receiveShadow == true and world.environment.shadows.enabled
    )
    send('cameraPosition', camera.worldPosition or camera.position)
    emitter._shadowSlots = emitter._shadowSlots or {}
    local count = 0
    emitter._lightPositions = emitter._lightPositions or {}
    emitter._lightColors = emitter._lightColors or {}
    emitter._lightDirections = emitter._lightDirections or {}
    if enabled then
        for slot, light in ipairs(renderer and renderer.lights.selected or world.lights) do
            if light.enabled and light:isVisible() then
                count = count + 1
                emitter._shadowSlots[count] = renderer
                        and world.layerGroups:interacts(
                            emitter.shadowGroup or 'Default',
                            light.shadowGroup or 'Default'
                        )
                        and slot - 1
                    or -1
                local p = light:getWorldPosition()
                local pos = emitter._lightPositions[count] or {}
                emitter._lightPositions[count] = pos
                pos[1], pos[2], pos[3], pos[4] =
                    p[1], p[2], p[3], light.type == 'DirectionalLight3D' and 0 or light.range
                local color = emitter._lightColors[count] or {}
                emitter._lightColors[count] = color
                color[1], color[2], color[3], color[4] =
                    light.color[1] / 255,
                    light.color[2] / 255,
                    light.color[3] / 255,
                    light.brightness
                local direction = emitter._lightDirections[count] or {}
                emitter._lightDirections[count] = direction
                if light:isA('DirectionalLight3D') then
                    local d = light.worldDirection
                    direction[1], direction[2], direction[3], direction[4] = d[1], d[2], d[3], -2
                elseif light:isA('SpotLight3D') then
                    local matrix = light:getWorldMatrix()
                    local dx, dy, dz = M.normalize(matrix[3], matrix[7], matrix[11])
                    direction[1], direction[2], direction[3], direction[4] =
                        dx, dy, dz, math.cos(math.rad(light.angle or 45))
                else
                    direction[1], direction[2], direction[3], direction[4] = 0, 0, 0, -2
                end
                if count == 8 then
                    break
                end
            end
        end
    end
    send('particleLightCount', count)
    if count > 0 then
        send('particleShadowSlot', unpack(emitter._shadowSlots, 1, count))
        send('particleLightPosition', unpack(emitter._lightPositions, 1, count))
        send('particleLightColor', unpack(emitter._lightColors, 1, count))
        send('particleLightDirection', unpack(emitter._lightDirections, 1, count))
    end
end

return L
