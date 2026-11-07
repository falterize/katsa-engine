-- A passenger's body on a car: the walker view's root becomes a child of the car's root, so it rides
-- along with the car's pose, and a Ramp moves it from where it stood to its seat (boarding) or the
-- other way (leaving). Seat positions come from game/seats.lua.
local Seats = require('../game.seats')
local Sequence = require('source.engine.animation.sequence')

local Rider = {}
Rider.__index = Rider

Rider.DURATION = 0.45 -- seconds to move between the ground and a seat
local SNAP_DISTANCE = 6 -- a walker further than this (just spawned, teleported) is not animated

-- `root` is the walker view's root node, `pivot` the child that carries the model.
function Rider.new(world, root, pivot)
    return setmetatable({ world = world, root = root, pivot = pivot, home = root.parent }, Rider)
end

local function wrap(angle)
    angle = angle % 360
    return angle > 180 and angle - 360 or angle
end

-- Plays a Ramp that moves `properties` (key -> { from, to }) of `node` with an ease in and out.
function Rider:animate(node, properties)
    if self.ramp then
        self.ramp:destroy()
    end
    local bindings = {}
    for key, ends in pairs(properties) do
        local track = Sequence.linear({ ends[1][1], ends[1][2], ends[1][3] }, ends[2])
        track[1].outgoing, track[2].incoming = { 0.35, 0 }, { 0.65, 1 }
        track.interpolation = 'Curve'
        bindings[key] = track
    end
    self.ramp = self.world:create('Ramp', {
        name = 'RiderRamp',
        mode = 'Animated',
        playbackTime = Rider.DURATION,
        bindings = bindings,
    }, node)
    self.ramp:play()
end

function Rider:isAttached()
    return self.carRoot ~= nil
end

-- Sits on `seat` of the car whose view root is `carRoot`. Called every frame; it only acts when the
-- car or the seat changed.
function Rider:board(carRoot, seat)
    if self.carRoot == carRoot and self.seat == seat then
        return
    end
    local target = Seats.offset(seat)
    local first = self.carRoot == nil and not self.placed
    self.root:setParent(carRoot, { keepWorldTransform = true })
    self.pivot.position = { 0, 0, 0 }
    self.carRoot, self.seat, self.placed = carRoot, seat, true
    local from = self.root.position
    local distance = math.sqrt(
        (from[1] - target[1]) ^ 2 + (from[2] - target[2]) ^ 2 + (from[3] - target[3]) ^ 2
    )
    if first or distance > SNAP_DISTANCE then
        self.root.position, self.root.rotation = target, { 0, 0, 0 }
        return
    end
    local turn = self.root.rotation
    self:animate(self.root, {
        position = { { from[1], from[2], from[3] }, target },
        rotation = { { wrap(turn[1]), wrap(turn[2]), wrap(turn[3]) }, { 0, 0, 0 } },
    })
end

-- Leaves the car: the root goes back to the world and the caller places it at the walker's own
-- position (`settle` then starts the exit move from the seat). `instant` skips the move.
function Rider:release(instant)
    if not self.carRoot then
        return
    end
    self.exitFrom = not instant and self.root:pointToWorldSpace({ 0, 0, 0 }) or nil
    if self.ramp then
        self.ramp:destroy()
        self.ramp = nil
    end
    self.root:setParent(self.home)
    self.carRoot, self.seat = nil, nil
end

-- After the root has its walking pose: the model starts at the seat it left and slides to the root.
function Rider:settle()
    local from = self.exitFrom
    if not from then
        return
    end
    self.exitFrom = nil
    local offset = self.root:pointToLocalSpace(from)
    self.pivot.position = offset
    self:animate(self.pivot, { position = { offset, { 0, 0, 0 } } })
end

return Rider
