-- Wheel damage. Body dents (deformation.lua) are cosmetic; this decides when a hard hit tears a
-- wheel off. Each wheel has health 1; an impact close to it takes some away, scaled by the impact
-- speed and the distance to the wheel. Pure Lua, so the server and every client agree.
--
--   local damage = Damage.new(car.detached)
--   local lost = damage:hit(impact, car.wheels)     -- list of wheel indexes torn off (or nil)
--   car.detached = damage.detached                  -- bit i-1 set: wheel i is gone
local Damage = {}
Damage.__index = Damage

Damage.REACH = 1.5 -- meters from the wheel center where an impact still hurts it
Damage.MIN_SPEED = 5 -- impacts slower than this (m/s) never hurt a wheel
Damage.TOUGHNESS = 16 -- speed above MIN_SPEED that tears a wheel off by itself

function Damage.new(detached)
    local self = setmetatable({ health = { 1, 1, 1, 1 }, detached = detached or 0 }, Damage)
    for index = 1, 4 do
        if self:isDetached(index) then
            self.health[index] = 0
        end
    end
    return self
end

function Damage:isDetached(index)
    return math.floor(self.detached / 2 ^ (index - 1)) % 2 == 1
end

function Damage.countDetached(mask)
    local count = 0
    for index = 1, 4 do
        count = count + (math.floor((mask or 0) / 2 ^ (index - 1)) % 2)
    end
    return count
end

-- impact: { x, y, z (car space), speed }. wheels: { {x, z}, ... } in car space.
function Damage:hit(impact, wheels)
    if impact.speed < Damage.MIN_SPEED then
        return nil
    end
    local lost
    local strength = (impact.speed - Damage.MIN_SPEED) / Damage.TOUGHNESS
    for index, wheel in ipairs(wheels) do
        if not self:isDetached(index) then
            local dx, dy, dz = impact.x - wheel[1], (impact.y or 0.4) - 0.4, impact.z - wheel[2]
            local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
            if distance < Damage.REACH then
                self.health[index] = self.health[index] - strength * (1.2 - distance / Damage.REACH)
                if self.health[index] <= 0 then
                    self.health[index] = 0
                    self.detached = self.detached + 2 ^ (index - 1)
                    lost = lost or {}
                    lost[#lost + 1] = index
                end
            end
        end
    end
    return lost
end

function Damage:repair()
    self.health = { 1, 1, 1, 1 }
    self.detached = 0
end

return Damage
