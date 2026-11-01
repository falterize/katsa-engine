local Gravity = {}

local function finite(value)
    return type(value) == 'number' and value == value and math.abs(value) < math.huge
end

function Gravity.vector(magnitude, direction, dimensions)
    assert(finite(magnitude) and magnitude >= 0, 'Gravity must be finite and nonnegative')
    assert(direction and #direction == dimensions, 'GravityDirection has invalid dimensions')
    local length = 0
    for i = 1, dimensions do
        assert(finite(direction[i]), 'GravityDirection must contain finite numbers')
        length = length + direction[i] ^ 2
    end
    local factor = length > 0 and magnitude / math.sqrt(length) or 0
    return direction[1] * factor,
        direction[2] * factor,
        dimensions == 3 and direction[3] * factor or nil
end

function Gravity.options(settings, dimensions, default)
    if type(settings.gravity) ~= 'number' and not settings.gravityDirection then
        local value = settings.gravity or default
        return { value[1], value[2], dimensions == 3 and value[3] or nil }
    end
    local direction = settings.gravityDirection or (dimensions == 3 and { 0, -1, 0 } or { 0, -1 })
    local magnitude = settings.gravity
    if type(magnitude) ~= 'number' then
        magnitude = 0
        for i = 1, dimensions do
            magnitude = magnitude + (settings.gravity or default)[i] ^ 2
        end
        magnitude = math.sqrt(magnitude)
    end
    return { Gravity.vector(magnitude, direction, dimensions) }
end

function Gravity.initialize(owner, dimensions)
    owner._gravityConfigured = owner.gravity ~= nil or owner.gravityDirection ~= nil
    owner._gravityDimensions = dimensions
    owner.gravity = owner.gravity or (dimensions == 3 and 196.2 or 627.84)
    owner.gravityDirection = owner.gravityDirection
        or (dimensions == 3 and { 0, -1, 0 } or { 0, -1 })
end

local function remember(physics)
    local owner, values = physics._gravityOwner, physics._gravityValues or {}
    physics._gravityValues = values
    values[1] = owner.gravity
    for i = 1, owner._gravityDimensions do
        values[i + 1] = owner.gravityDirection[i]
    end
end

function Gravity.read(physics, x, y, z)
    local owner = physics._gravityOwner
    if not owner or physics._applyingGravity then
        return
    end
    local length = math.sqrt(x * x + y * y + (z or 0) ^ 2)
    owner.gravity = length
    if length > 0 then
        owner.gravityDirection[1], owner.gravityDirection[2] = x / length, y / length
        if owner._gravityDimensions == 3 then
            owner.gravityDirection[3] = z / length
        end
    end
    remember(physics)
end

function Gravity.bind(owner, physics)
    physics._gravityOwner = owner
    local dimensions = owner._gravityDimensions
    local default = dimensions == 3 and 196.2 or 627.84
    local configured = owner._gravityConfigured or owner.gravity ~= default
    local direction = owner.gravityDirection
    configured = configured
        or direction[1] ~= 0
        or direction[2] ~= -1
        or dimensions == 3 and direction[3] ~= 0
    if configured then
        Gravity.apply(physics)
    else
        local vector = physics.gravity
        Gravity.read(physics, vector[1], vector[2], vector[3])
    end
end

function Gravity.apply(physics)
    local owner = physics._gravityOwner
    if not owner then
        return
    end
    local values, changed = physics._gravityValues, false
    if values then
        changed = values[1] ~= owner.gravity
        for i = 1, owner._gravityDimensions do
            changed = changed or values[i + 1] ~= owner.gravityDirection[i]
        end
        if not changed then
            return
        end
    end
    local x, y, z = Gravity.vector(owner.gravity, owner.gravityDirection, owner._gravityDimensions)
    physics._applyingGravity = true
    physics:setGravity(x, y, z)
    physics._applyingGravity = nil
    remember(physics)
end

return Gravity
