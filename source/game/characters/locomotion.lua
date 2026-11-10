local Math = require('./math')

local Locomotion = {}

function Locomotion.ground(player, dt, speed, scale, walking, crouching)
    local settings, velocity = player.settings, player.velocity
    player:gravity(dt)
    player:rotateVisual()
    player:setWalkScale(scale)
    player.crouchBlend =
        Math.approach(player.crouchBlend, crouching and 1 or 0, settings.blendSpeed * dt)
    local moving = player:moving()
    if
        (crouching or player.targetHeight > settings.crouchingHeight) and (not walking or moving)
    then
        player.walkBlend =
            Math.approach(player.walkBlend, walking and 1 or 0, settings.blendSpeed * dt)
    end
    if walking and not crouching and not moving then
        return
    end
    local amount = (moving and walking and settings.acceleration or settings.friction) * dt
    velocity[1] = Math.approach(velocity[1], player.direction[1] * speed, amount)
    velocity[3] = Math.approach(velocity[3], player.direction[3] * speed, amount)
end

function Locomotion.transition(player)
    if not player.grounded then
        return 'fall'
    elseif player.input.crouch then
        return 'crouch'
    elseif player.input.jump then
        return 'jump'
    end
end

function Locomotion.air(player, dt)
    player:gravity(dt)
    player:rotateVisual()
    if player:moving() then
        local amount = player.settings.acceleration * dt
        player.velocity[1] = Math.approach(
            player.velocity[1],
            player.direction[1] * player.settings.walkSpeed,
            amount
        )
        player.velocity[3] = Math.approach(
            player.velocity[3],
            player.direction[3] * player.settings.walkSpeed,
            amount
        )
    end
end

return Locomotion
