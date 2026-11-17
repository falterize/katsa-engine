-- The player body: an axis-aligned box that walks, jumps and flies through the block world.
-- Movement is resolved axis by axis in steps shorter than a block, so it never tunnels.
local Walker = {}
Walker.__index = Walker

local HALF, HEIGHT, EPSILON, STEP = 0.3, 1.8, 1e-4, 0.1

function Walker.new(world, settings)
    return setmetatable({
        world = world,
        settings = settings,
        x = 0, y = 0, z = 0,
        vx = 0, vy = 0, vz = 0,
        onGround = false,
        flying = false,
        -- Walking input: forward/strafe in -1..1; jump and descend are held keys.
        forward = 0, strafe = 0, jump = false, descend = false, sprint = false,
        yaw = 0,
    }, Walker)
end

function Walker:teleport(x, y, z)
    self.x, self.y, self.z, self.vx, self.vy, self.vz = x, y, z, 0, 0, 0
end

function Walker:toggleFly()
    self.flying = not self.flying
    self.vy = 0
end

-- True when the box at this feet position overlaps a solid block (unloaded chunks are solid).
function Walker:collides(x, y, z)
    local world = self.world
    for bx = math.floor(x - HALF), math.floor(x + HALF) do
        for bz = math.floor(z - HALF), math.floor(z + HALF) do
            for by = math.floor(y), math.floor(y + HEIGHT - EPSILON) do
                if world:isSolid(bx, by, bz) then
                    return true
                end
            end
        end
    end
    return false
end

local function moveAxis(self, axis, amount)
    local steps = math.max(1, math.ceil(math.abs(amount) / STEP))
    local part = amount / steps
    for _ = 1, steps do
        local x, y, z = self.x, self.y, self.z
        if axis == 'x' then
            x = x + part
        elseif axis == 'y' then
            y = y + part
        else
            z = z + part
        end
        if self:collides(x, y, z) then
            -- Snap against the face that was hit, then stop moving along this axis.
            if axis == 'x' then
                self.x = part > 0 and math.floor(x + HALF) - HALF - EPSILON
                    or math.floor(x - HALF) + 1 + HALF + EPSILON
                self.vx = 0
            elseif axis == 'z' then
                self.z = part > 0 and math.floor(z + HALF) - HALF - EPSILON
                    or math.floor(z - HALF) + 1 + HALF + EPSILON
                self.vz = 0
            elseif part < 0 then
                self.y, self.onGround = math.floor(y) + 1, true
                self.vy = 0
            else
                self.y = math.floor(y + HEIGHT) - HEIGHT - EPSILON
                self.vy = 0
            end
            return
        end
        self.x, self.y, self.z = x, y, z
    end
end

function Walker:update(dt)
    local s = self.settings
    dt = math.min(dt, 0.05)
    local sin, cos = math.sin(math.rad(self.yaw)), math.cos(math.rad(self.yaw))
    -- Camera yaw: forward is (sin, cos) on the ground plane, right is (cos, -sin).
    local dirX = sin * self.forward + cos * self.strafe
    local dirZ = cos * self.forward - sin * self.strafe
    local length = math.sqrt(dirX * dirX + dirZ * dirZ)
    if length > 1 then
        dirX, dirZ = dirX / length, dirZ / length
    end
    local speed
    if self.flying then
        speed = self.sprint and s.flySprintSpeed or s.flySpeed
        self.vy = ((self.jump and 1 or 0) - (self.descend and 1 or 0)) * speed
    else
        speed = self.sprint and s.sprintSpeed or s.walkSpeed
        if self.descend then
            speed = speed * 0.3 -- sneaking
        end
        self.vy = self.vy - s.gravity * dt
        if self.jump and self.onGround then
            self.vy = s.jumpSpeed
        end
    end
    -- Horizontal velocity eases toward the wanted one: quick on the ground, floaty in the air.
    local blend = math.min(1, dt * ((self.flying or self.onGround) and 14 or 3))
    self.vx = self.vx + (dirX * speed - self.vx) * blend
    self.vz = self.vz + (dirZ * speed - self.vz) * blend
    self.onGround = false
    moveAxis(self, 'x', self.vx * dt)
    moveAxis(self, 'z', self.vz * dt)
    moveAxis(self, 'y', math.max(self.vy * dt, -2))
    if self.flying and self.onGround then
        self.flying = false -- landing while flying walks again
    end
    if self.y < -20 then
        self:teleport(self.x, self.world.blocks.HEIGHT, self.z)
    end
end

function Walker:overlapsBlock(bx, by, bz)
    return bx + 1 > self.x - HALF
        and bx < self.x + HALF
        and by + 1 > self.y
        and by < self.y + HEIGHT
        and bz + 1 > self.z - HALF
        and bz < self.z + HALF
end

return Walker
