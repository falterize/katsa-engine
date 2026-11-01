local modes = { Linear = true, LinearSquare = true, Inverse = true }

local function unit(value, label)
    assert(
        type(value) == 'number' and value >= 0 and value <= 1,
        label .. ' must be between 0 and 1'
    )
end
return { modes = modes, unit = unit }
