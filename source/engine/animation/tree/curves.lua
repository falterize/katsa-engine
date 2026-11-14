-- Fade curves shared by Transition and StateMachine: a name or a function of 0..1.
local Curves = {}

local named = {
    linear = function(t)
        return t
    end,
    smooth = function(t)
        return t * t * (3 - 2 * t)
    end,
    easeIn = function(t)
        return t * t
    end,
    easeOut = function(t)
        return 1 - (1 - t) * (1 - t)
    end,
}

Curves.names = { 'linear', 'smooth', 'easeIn', 'easeOut' }

function Curves.get(curve)
    curve = curve or 'linear'
    if type(curve) == 'function' then
        return curve
    end
    return assert(named[curve], 'Unknown curve: ' .. tostring(curve))
end

return Curves
