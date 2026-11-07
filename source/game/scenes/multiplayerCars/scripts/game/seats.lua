-- Where each seat of a car is. Four seats: the driver and the front passenger sit in the cabin, the
-- other two passengers sit on the hood and on the trunk lid. Positions are in car-model space (the
-- frame of the car view: +z forward, +x right, y up from the ground below the chassis), measured on
-- the Duke 69 (`--test-v108.7.carbounds`): the steering wheel is at x +0.34, the hood top at
-- y 0.97 over z 1.1..2.6 and the trunk lid top at y 1.0 over z -2.6..-1.8.
local Seats = {}

Seats.COUNT = 4

local layout = {
    { kind = 'cabin', x = 0.4, y = 0.3, z = -0.15 }, -- driver
    { kind = 'cabin', x = -0.4, y = 0.3, z = -0.15 }, -- front passenger
    { kind = 'hood', x = 0, y = 0.97, z = 1.75 },
    { kind = 'trunk', x = 0, y = 1.0, z = -2.15 },
}

function Seats.layout(index)
    return assert(layout[index], 'No such seat: ' .. tostring(index))
end

-- Seat position in car-model space.
function Seats.offset(index)
    local seat = Seats.layout(index)
    return { seat.x, seat.y, seat.z }
end

function Seats.isDriver(index)
    return index == 1
end

return Seats
