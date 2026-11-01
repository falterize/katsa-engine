-- Scene node folder nodes/vehicle: driving, suspension, nitro, seats, collisions and body dents.
-- The parts are pure Lua, so they load here the way a scene package resolves `scene.` requires.
local load = require('validation.tests.katsa.sceneRequire')
local function sceneRequire(name)
    return load('multiplayerCars', name)
end
local Vehicle = {
    Collision = sceneRequire('scene.nodes.vehicle.collision'),
    Deformation = sceneRequire('scene.nodes.vehicle.deformation'),
}
Vehicle.new = sceneRequire('scene.nodes.vehicle.model').new

return function(T)
    local function run(car, input, seconds)
        for _ = 1, math.floor(seconds * 60) do
            car:step(input, 1 / 60)
        end
    end

    local car = Vehicle.new()
    run(car, { throttle = 1 }, 4)
    T.check(
        car.speed > 15 and car.speed <= car.config.maxSpeed,
        'vehicle: accelerates toward top speed'
    )
    T.check(car.z > 20 and math.abs(car.x) < 1e-6, 'vehicle: drives straight along heading 0')

    -- Determinism: the same inputs give the same state (server and prediction must agree).
    local a, b = Vehicle.new(), Vehicle.new()
    for tick = 1, 300 do
        local input = { throttle = 1, steer = math.sin(tick / 30), nitro = tick % 100 < 20 }
        a:step(input, 1 / 60)
        b:step(input, 1 / 60)
    end
    T.check(a.x == b.x and a.z == b.z and a.heading == b.heading, 'vehicle: step is deterministic')

    local turning = Vehicle.new()
    run(turning, { throttle = 1, steer = 1 }, 2)
    T.check(turning.heading ~= 0 and turning.x > 0, 'vehicle: positive steer turns right')

    local braking = Vehicle.new()
    run(braking, { throttle = 1 }, 3)
    local before = braking.speed
    run(braking, { throttle = -1 }, 1)
    T.check(braking.speed < before - 10, 'vehicle: brakes')

    local boosted, plain = Vehicle.new(), Vehicle.new()
    run(boosted, { throttle = 1, nitro = true }, 3)
    run(plain, { throttle = 1 }, 3)
    T.check(
        boosted.speed > plain.speed and boosted.nitro < 1,
        'vehicle: nitro is faster and drains'
    )
    run(boosted, { throttle = 1, nitro = true }, 6)
    T.check(boosted.nitro == 0, 'vehicle: nitro runs out')
    boosted:addNitro(2)
    T.check(boosted.nitro == 1, 'vehicle: refill is clamped to a full tank')

    -- Suspension reacts to a bump under the wheels and settles again.
    local bump = Vehicle.new({}, function(x, z)
        return (z > 4 and z < 5) and 0.4 or 0
    end)
    run(bump, { throttle = 1 }, 1)
    local moved = false
    for _ = 1, 120 do
        bump:step({ throttle = 0.3 }, 1 / 60)
        moved = moved or math.abs(bump.spring[1]) > 0.01
    end
    T.check(moved, 'vehicle: springs compress over a bump')
    local flat = Vehicle.new()
    run(flat, { throttle = 1 }, 1)
    T.check(
        math.abs(flat.spring[1]) < 1e-6 and math.abs(flat.y - flat.config.rideHeight) < 1e-6,
        'vehicle: flat ground keeps the ride height'
    )

    -- Seats.
    local seated = Vehicle.new()
    T.check(seated:sit(10) == 1 and seated:getDriver() == 10, 'vehicle: first rider drives')
    seated:sit(11)
    seated:sit(12)
    seated:sit(13)
    T.check(seated:sit(14) == nil and seated:getOccupants() == 4, 'vehicle: only four fit')
    T.check(seated:sit(12) == 3, 'vehicle: sitting again keeps the seat')
    seated:leave(10)
    T.check(seated:getDriver() == nil and seated:sit(14) == 1, 'vehicle: a freed seat is reused')

    -- Collisions.
    local crash = Vehicle.new()
    crash:setPose(0, 0, 0)
    run(crash, { throttle = 1 }, 2)
    local impacts = {}
    for _ = 1, 120 do
        crash:step({ throttle = 1 }, 1 / 60)
        local hits = Vehicle.Collision.resolveStatic(crash, {
            { kind = 'box', x = 0, z = 30, halfX = 5, halfZ = 1 },
        })
        for _, hit in ipairs(hits) do
            impacts[#impacts + 1] = hit
        end
    end
    T.check(#impacts > 0 and crash.z < 30 - 1 + 0.01, 'vehicle: a wall stops the car')
    T.check(impacts[1].z > 0, 'vehicle: front impact is at the front of the car')

    local dents = Vehicle.Deformation.new()
    local dent
    for _, hit in ipairs(impacts) do
        dent = dent or dents:addImpact(hit)
    end
    T.check(dent ~= nil and dent.depth > 0, 'vehicle: a hard hit creates a dent')
    T.check(
        dents:addImpact({ x = 0, z = 1, nx = 0, nz = -1, speed = 1 }) == nil,
        'vehicle: a gentle bump leaves no dent'
    )
    local ox, _, oz = dents:offsetAt(dent.x, dent.y, dent.z)
    T.check(math.abs(ox) + math.abs(oz) > 0, 'vehicle: vertices near the dent move')
    local far = { dents:offsetAt(dent.x + 10, dent.y, dent.z) }
    T.check(far[1] == 0 and far[3] == 0, 'vehicle: far vertices stay put')
    local copy = Vehicle.Deformation.new()
    copy:load(dents:serialize())
    local cx, _, cz = copy:offsetAt(dent.x, dent.y, dent.z)
    T.check(cx == ox and cz == oz, 'vehicle: dents survive serialization')

    local one, two = Vehicle.new(), Vehicle.new()
    one:setPose(0, 0, 90)
    two:setPose(3, 0, 270)
    one.speed, two.speed = 10, 10
    local first = Vehicle.Collision.resolvePair(one, two)
    T.check(#first > 0 and one.speed < 10, 'vehicle: head-on cars bounce apart')
end
