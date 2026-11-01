local QueryPolicy = {}

function QueryPolicy.accepts(physics, body)
    if not body or body.destroyed or not body.canQuery or body.colliderEnabled == false then
        return false
    end

    -- Filters are user callbacks: they may destroy the candidate body. Native
    -- removal is deferred by raycast(), but the wrapper must be checked again.
    if physics.rayFilter and not physics.rayFilter(body) then
        return false
    end
    return not body.destroyed
end

return QueryPolicy
