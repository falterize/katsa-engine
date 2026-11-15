-- Seated at the wheel: the car owns the motion; the walker body rides along, collision off.
local Drive = {}

function Drive.enter(walker)
    walker:setRiding(true)
end

function Drive.exit(walker)
    walker:setRiding(false)
end

function Drive.update(walker)
    walker:rideAlong()
end

return Drive
