local requests = { Jump = 'jump', Dash = 'dash', Slide = 'slide', Respawn = 'respawn' }
local Player = {}
Player.__index = Player

function Player.new(state)
    local self = setmetatable({
        state = state,
        jumps = 0,
        facing = 1,
        dashTime = 0,
        dashCooldown = 0,
        slideTime = 0,
        motion = 'Idle',
    }, Player)
    local actions = state.scene.input.actions
    for name, key in pairs({ Dash = 'lshift', Slide = 'c', Respawn = 'r' }) do
        if actions.values[name] == nil then
            actions:define(name, { key = key })
        end
    end
    for name, request in pairs(requests) do
        actions:on(name, function()
            self:request(request)
        end)
    end
    self.filter = function(body)
        return body.object ~= state.player and body.object.isTrigger ~= true
    end
    self.rayStart, self.rayEnd, self.rayHit = {}, {}, {}
    return self
end

function Player:request(action)
    self[action .. 'Requested'] = true
end

function Player:checkpoint(index)
    local state = self.state
    if index <= state.checkpoint then
        return
    end
    state.checkpoint = index
    local checkpoint = state.checkpoints[index]
    state.spawn = { checkpoint.spawn[1], checkpoint.spawn[2] }
    checkpoint.visual.backgroundColor = { 0.3, 1, 0.55 }
    state.burst:emit(40)
    state.scene.audio:play('shared://audio/effects/chime.wav', { volume = 0.25 })
end

function Player:respawn()
    local state = self.state
    state.deaths = state.deaths + 1
    state.player.body:teleport(state.spawn, 0)
    state.player.body:setVelocity({ 0, 0 })
    state.player.gravityScale = 1
    self.jumps, self.dashTime, self.slideTime = 0, 0, 0
    state.trail.rate = 0
    self.jumpRequested, self.dashRequested, self.slideRequested = false, false, false
end

function Player:update(dt)
    if dt <= 0 then
        return
    end
    local state, object = self.state, self.state.player
    local body = object.body
    -- Minimal hosts do not dispatch action listeners; consume the same named
    -- actions here as well, without polling OS keys or changing mobile controls.
    local actions = state.scene.input.actions
    for name, request in pairs(requests) do
        if actions:consume(name) then
            self:request(request)
        end
    end
    if self.respawnRequested then
        self.respawnRequested = false
        self:respawn()
    end
    self.dashCooldown = math.max(0, self.dashCooldown - dt)
    self.dashTime, self.slideTime =
        math.max(0, self.dashTime - dt), math.max(0, self.slideTime - dt)
    local x, y = body:getPosition()
    self.rayStart[1], self.rayStart[2] = x, y
    self.rayEnd[1], self.rayEnd[2] = x, y - state.collider.size[2] / 2 - 3
    local hit = state.physics:raycast(self.rayStart, self.rayEnd, self.filter, self.rayHit)
    local vx, vy = body:getLinearVelocity()
    self.grounded = hit ~= nil and hit.normal[2] > 0.4 and vy <= 1
    if self.grounded then
        self.jumps = 0
    end
    local move = state.scene.input.actions:value('Move')[1]
    if next(state.touchLeft) then
        move = move - 1
    end
    if next(state.touchRight) then
        move = move + 1
    end
    move = math.max(-1, math.min(1, move))
    if move ~= 0 then
        self.facing = move > 0 and 1 or -1
    end
    if self.jumpRequested and self.jumps < 2 then
        vy, self.jumps = 310, self.jumps + 1
        self.grounded = false
    end
    if self.dashRequested and self.dashCooldown == 0 then
        self.dashTime, self.dashCooldown = 0.18, 0.7
    end
    if self.slideRequested and self.grounded then
        self.slideTime = 0.35
    end
    self.jumpRequested, self.dashRequested, self.slideRequested = false, false, false
    object.gravityScale = self.dashTime > 0 and 0 or 1
    if self.dashTime > 0 then
        vx, vy, self.motion = self.facing * 480, 0, 'Dash'
    elseif self.slideTime > 0 then
        vx, self.motion = self.facing * 260, 'Slide'
    else
        vx = move * 170
        self.motion = not self.grounded and 'Jump' or move ~= 0 and 'Run' or 'Idle'
    end
    -- Keep the feet fixed when changing the collider for the slide ability.
    local height = self.slideTime > 0 and 16 or 32
    if state.collider.size[2] ~= height then
        body:teleport(x, y + (height - state.collider.size[2]) / 2, 0)
        state.collider.size[2] = height
    end
    state.effects.update(state, self)
    body:setLinearVelocity(vx, vy)
    if y < -180 then
        self:respawn()
    end
end

return Player
