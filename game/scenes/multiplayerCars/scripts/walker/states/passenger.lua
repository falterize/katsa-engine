local Passenger = {}

function Passenger.enter(walker)
    walker:setRiding(true)
end

function Passenger.exit(walker)
    walker:setRiding(false)
end

function Passenger.update(walker)
    walker:rideAlong()
end

return Passenger
